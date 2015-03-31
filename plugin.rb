# name: oort
# about: Customisation for Oort Online
# version: 1.0.0
# authors: Simon

after_initialize do
  require_dependency File.expand_path('../jobs/check_recent_users.rb', __FILE__)
end
