# This should live somewhere in your load path. Eg. Initializers folder.
class MyFakeUser < FakeUser

  def role
    "public_user"
  end

  def resources
    Typus::Configuration.roles[role.to_s].compact
  end

  def can?(action, resource, options = {})
    resource = resource.model_name if resource.is_a?(Class)

    return false if !resources.include?(resource)
    return true if resources[resource].include?("all")

    action = options[:special] ? action : action.acl_action_mapper

    resources[resource].extract_settings.include?(action)
  end

  def applications
    Typus.applications.delete_if { |a| application(a).empty? }
  end

  def application(name)
    Typus.application(name).delete_if { |r| !resources.keys.include?(r) }
  end

end
