# A workaraound to get `reload!` to also call Apartment::Tenant.init
# This is unfortunate, but I haven't figured out how to hook into the reload process *after* files are reloaded

# reloads the environment
def reload!(print=true)
  puts "Reloading..." if print
  if Rails.application.reloader.respond_to?(:reload!)
    Rails.application.reloader.reload!
  end
  # Manually init Apartment again once classes are reloaded
  Apartment::Tenant.init
  true
end
