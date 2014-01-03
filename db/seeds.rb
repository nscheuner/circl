tasks = %w{languages
           private_tags
           public_tags
           application_settings
           query_presets
           jobs
           roles
           locations
           ldap_attributes
           search_attributes
           salary_templates
           generic_templates
           invoice_templates
           task_types
           task_rates}

tasks.each do |task|
  Rake::Task["db:seed:#{task}:create"].invoke
end

# Schedule that we need to generate the invoice templates' screenshots
# *after* the server has started, otherwise it cannot serve assets
# needed for the snapshot creation
BackgroundTasks::RunRakeTask.create!(:options => { :name => 'db:seed:invoice_templates:snapshots:reset' })
BackgroundTasks::RunRakeTask.create!(:options => { :name => 'db:seed:generic_templates:snapshots:reset' })
