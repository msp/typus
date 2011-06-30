module Typus
  module Authentication
    module Public

      protected

      include Base

      def authenticate
        @admin_user = MyFakeUser.new
      end

      def check_if_user_can_perform_action_on_resources
        if admin_user.cannot?(params[:action], @resource.model_name)
          not_allowed
        end
      end

      def not_allowed
        render :text => "Not allowed!", :status => :unprocessable_entity
      end

    end
  end
end
