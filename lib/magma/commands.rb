require 'date'
require 'logger'

class Magma
  class Help < Etna::Command
    usage 'List this help'

    def execute
      puts 'Commands:'
      Magma.instance.commands.each do |name,cmd|
        puts cmd.usage
      end
    end
  end

  class Migrate < Etna::Command
    usage '[<project_name> [<version_number>]] # Run migrations for project(s). Use project "magma" for base migrations'

    def execute(project_name=nil, version=nil)
      Sequel.extension(:migration)
      @db = Magma.instance.db

      run_magma_migration(version) if !project_name || project_name == 'magma'
      run_project_migrations(project_name, version)
    end

    def run_magma_migration(version)
      table = "schema_info_magma"
      if version
        puts "Migrating to version #{version}"
        Sequel::Migrator.run(@db, 'db/migrations', table: table, target: version.to_i)
      else
        puts 'Migrating to latest'
        Sequel::Migrator.run(@db, 'db/migrations', table: table)
      end
    end

    def run_project_migrations(project_name, version)
      Magma.instance.config(:project_path).split(/\s+/).each do |project_dir|
        m_project_name = ::File.basename(project_dir)
        next if project_name && project_name != m_project_name

        table = "schema_info_#{project_dir.gsub(/[^\w]+/,'_').sub(/^_/,'').sub(/_$/,'')}"
        if version
          puts "Migrating to version #{version}"
          Sequel::Migrator.run(@db, File.join(project_dir, 'migrations'), table: table, target: version.to_i)
        else
          puts 'Migrating to latest'
          Sequel::Migrator.run(@db, File.join(project_dir, 'migrations'), table: table)
        end
      end
    end

    def setup(config)
      super
      Magma.instance.setup_db
    end
  end

  # When building migrations from scratch this command does not output
  # an order that respects foreign key constraints. i.e. The order in which the
  # migration creates tries to create the tables is out of whack and causes 
  # error messages that tables are required but do not exist. Most of the time 
  # this is not an issue (because we are only doing slight modifications), but
  # when we do a new migration of an established database errors do arise.
  # Presently we are manually reorgaizing the initial migration (putting the
  # the table creation in the correct order), but we should add logic here so
  # we do not have to in the future.
  class Plan < Etna::Command
    usage '[<project_name>] # Suggest a migration based on the current model attributes.'

    def execute(project_name=nil)
      if project_name
        project = Magma.instance.get_project(project_name)
        raise ArgumentError, "No such project #{project_name}!" unless project
        projects = [ project ]
      else
        projects = Magma.instance.magma_projects.values
      end
      puts <<EOT
Sequel.migration do
  change do
#{projects.map(&:migrations).flatten.join("\n")}
  end
end
EOT
    end

    def setup(config)
      super
      Magma.instance.load_models(false)
    end
  end

  class Console < Etna::Command
    usage 'Open a console with a connected magma instance.'

    def execute
      require 'irb'
      ARGV.clear
      IRB.start
    end

    def setup(config)
      super
      Magma.instance.load_models
    end
  end

  class Load < Etna::Command
    usage 'Run data loaders on project models.'

    def execute(project_name=nil, loader_name=nil, *args)
      loaders = Magma.instance.find_descendents(Magma::Loader)

      if !project_name || !loader_name
        # List available loaders
        puts 'Available loaders:'
        puts "\nmagma"
        Magma::Loader.list.select do |loader|
          loader.project_name == :magma
        end.each do |loader|
          puts "%30s  %s" % [ loader.loader_name, loader.description ]
        end

        Magma.instance.magma_projects.each do |project_name, project|
          puts "\n#{project_name}"
          project.loaders.select do |loader|
            loader.project_name == project_name
          end.each do |loader|
            puts "%30s  %s" % [ loader.loader_name, loader.description ]
          end
        end
        exit
      end

      loader = Magma.instance.get_project(project_name).get_loader(loader_name)

      raise "Could not find a loader named #{loader_name}" unless loader

      begin
        loader.new(project_name, loader.arguments.keys.zip(args).to_h).load
      rescue Magma::LoadFailed => e
        puts "Load failed with these complaints:"
        puts e.complaints
      end
    end

    def setup(config)
      super
      Magma.instance.load_models
    end
  end

  class Unload < Etna::Command
    usage '<project_name> <model_name> # Dump the dataset of the model into a tsv'

    def execute(project_name, model_name)
      require_relative './payload'
      require_relative './retrieval'
      require_relative './tsv_writer'

      begin
        model = Magma.instance.get_model(project_name, model_name)
        retrieval = Magma::Retrieval.new(model, 'all', 'all', page: 1, page_size: 100_000)
        payload = Magma::Payload.new
        Magma::TSVWriter.new(model, retrieval, payload).write_tsv{ |lines| puts lines }
      rescue Exception => e
        puts "Unload failed:"
        puts e.message
      end
    end

    def setup(config)
      super
      Magma.instance.load_models
      Magma.instance.setup_db
    end
  end
end
