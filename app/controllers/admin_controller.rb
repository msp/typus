class AdminController < ApplicationController

  layout 'typus'

  include Authentication
  include Typus::Export
  include Typus::Configuration::Reloader

  if Typus::Configuration.options[:ssl]
    include SslRequirement
    ssl_required :index, :new, :create, :edit, :show, :update, :destroy, :toggle, :position, :relate, :unrelate
  end

  before_filter :reload_config_et_roles

  before_filter :require_login

  before_filter :set_resource
  before_filter :find_record, :only => [ :show, :edit, :update, :destroy, :toggle, :position ]

  before_filter :can_perform_action_on_typus_user?, :only => [ :edit, :update, :toggle, :destroy ]
  before_filter :can_perform_action?

  before_filter :set_order_and_list_fields, :only => [ :index ]
  before_filter :set_form_fields, :only => [ :new, :edit, :create, :update ]

  ##
  # This is the main index of the model. With the filters, conditions 
  # and more. You can get HTML, CSV and XML listings.
  #
  def index

    # Build the conditions
    conditions = @resource[:class].build_conditions(params)

    # Pagination
    items_count = @resource[:class].count(:conditions => conditions)
    items_per_page = Typus::Configuration.options[:per_page].to_i
    @pager = ::Paginator.new(items_count, items_per_page) do |offset, per_page|
      @resource[:class].find(:all, 
                             :conditions => conditions, 
                             :order => @order, 
                             :limit => per_page, 
                             :offset => offset)
    end

    @items = @pager.page(params[:page])

    # Respond with HTML, CSV and XML versions. This feature is only 
    # available on the index as is where we usually need those file 
    # versions.
    respond_to do |format|
      format.html { select_template :index }
      format.csv { generate_csv }
      format.xml  { render :xml => @items.items }
    end

  rescue Exception => error
    error_handler(error)
  end

  ##
  # New record.
  #
  def new

    item_params = params.dup
    %w( action controller model model_id back_to selected ).each do |param|
      item_params.delete(param)
    end

    @item = @resource[:class].new(item_params.symbolize_keys)

    select_template :new

  end

  ##
  # Create new records. There's an special case when we create a 
  # record from another record. In this case, after the record is 
  # created we create also the relationship between these models. 
  #
  def create
    @item = @resource[:class].new(params[:item])
    if @item.valid?
      if params[:back_to]
        if params[:model] && params[:model_id]
          model_to_relate = params[:model].constantize
          if @item.respond_to?(params[:model].tableize)
            @item.save
            # This is the case of habtm
            @item.send(params[:model].tableize) << model_to_relate.find(params[:model_id])
          else
            # This is the case of a polymorphic relationship.
            model_to_relate.find(params[:model_id]).send(@item.class.name.tableize).create(params[:item])
          end
          flash[:success] = "%s successfully assigned to %s." % [ @item.class, params[:model].downcase ]
          redirect_to params[:back_to]
        else
          @item.save
          flash[:success] = "New %s created." % @resource[:class_name_humanized]
          redirect_to "#{params[:back_to]}?#{params[:selected]}=#{@item.id}"
        end
      else
        @item.save
        flash[:success] = "%s successfully created." % @resource[:class_name_humanized]
        if Typus::Configuration.options[:edit_after_create]
          redirect_to :action => 'edit', :id => @item.id
        else
          redirect_to :action => 'index'
        end
      end
    else
      select_template :new
    end
  end

  ##
  # Edit a record.
  #
  def edit
    item_params = params.dup
    %w( action controller model model_id back_to id ).each { |p| item_params.delete(p) }
    # We assign the params passed trough the url
    @item.attributes = item_params
    @previous, @next = @item.previous_and_next
    select_template :edit
  end

  ##
  # Show a record.
  #
  def show
    @previous, @next = @item.previous_and_next
    select_template :show
  end

  ##
  # Update a record.
  #
  def update
    if @item.update_attributes(params[:item])
      flash[:success] = "%s successfully updated." % @resource[:class_name_humanized]
      if Typus::Configuration.options[:edit_after_create]
        redirect_to :action => 'edit', :id => @item.id
      else
        redirect_to :action => 'index'
      end
    else
      select_template :edit
    end
  end

  ##
  # Destroy a record.
  #
  def destroy
    @item.destroy
    flash[:success] = "%s successfully removed." % @resource[:class_name_humanized]
    redirect_to :back
  rescue Exception => error
    error_handler(error, { :params => params.merge(:action => 'index', :id => nil) })
  end

  ##
  # Toggle the status of an item.
  #
  def toggle
    if Typus::Configuration.options[:toggle]
      @item.toggle!(params[:field])
      flash[:success] = "%s %s changed." % [ @resource[:class_name_humanized], params[:field] ]
    else
      flash[:warning] = "Toggle is disabled."
    end
    redirect_to :back
  end

  ##
  # Change item position. This only works if acts_as_list is 
  # installed. We can then move items:
  #
  #   params[:go] = 'move_to_top'
  #   params[:go] = 'move_higher'
  #   params[:go] = 'move_lower'
  #   params[:go] = 'move_to_bottom'
  #
  def position
    @item.send(params[:go])
    flash[:success] = "Record moved %s." % params[:go].gsub(/move_/, '').humanize.downcase
    redirect_to :back
  end

  ##
  # Relate a model object to another.
  #
  def relate
    model_to_relate = params[:related][:model].constantize
    @resource[:class].find(params[:id]).send(params[:related][:model].tableize) << model_to_relate.find(params[:related][:id])
    flash[:success] = "%s added to %s." % [ model_to_relate.to_s.titleize , @resource[:class_name_humanized] ]
    redirect_to :back
  end

  ##
  # Remove relationship between models.
  #
  def unrelate
    model_to_unrelate = params[:model].constantize
    unrelate = model_to_unrelate.find(params[:model_id])
    if @resource[:class].find(params[:id]).respond_to?(params[:model].tableize)
      # Unrelate a habtm
      @resource[:class].find(params[:id]).send(params[:model].tableize).delete(unrelate)
      flash[:success] = "%s removed from %s." % [ model_to_unrelate.to_s.titleize, @resource[:class_name_humanized] ]
    else
      # Unrelate a polymorphic relationship
      @resource[:class].find(params[:id]).destroy
      flash[:success] = "%s removed from %s." % [ @resource[:class_name_humanized], model_to_unrelate.to_s.downcase ]
    end
    redirect_to :back
  end

private

  ##
  # Set current resource.
  #
  def set_resource
    resource = params[:controller].split("/").last
    @resource = {}
    @resource[:class] = resource.to_class
    @resource[:class_name] = resource.to_class.name
    @resource[:class_name_humanized] = resource.to_class.name.titleize
    @resource[:table_name] = resource.to_class.table_name
  rescue Exception => error
    error_handler(error)
  end

  ##
  # Find model when performing an edit, update, destroy, relate, 
  # unrelate ...
  #
  def find_record
    @item = @resource[:class].find(params[:id])
  end

  ##
  # Set fields and order when performing an index action.
  #
  def set_order_and_list_fields
    @order = params[:order_by] ? "#{params[:order_by]} #{params[:sort_order]}" : @resource[:class].typus_order_by
    @fields = @resource[:class].typus_fields_for(:list)
  end

  ##
  # Model +form_fields+ and +form_fields_externals+
  #
  def set_form_fields
    @item_fields = @resource[:class].typus_fields_for(:form)
    @item_relationships = @resource[:class].typus_relationships
  end

  ##
  # Select which template to render.
  #
  def select_template(template, resource = @resource[:table_name])
    if File.exists?("app/views/admin/#{resource}/#{template}.html.erb")
      render :template => "admin/#{resource}/#{template}"
    else
      render :template => "admin/#{template}"
    end
  end

  ##
  # Error handler
  #
  def error_handler(error, redirection = typus_dashboard_url)
    if Rails.env.production?
      flash[:error] = error.message + "(#{@resource[:class]})"
      redirect_to redirection
    else
      raise error
    end
  end

end