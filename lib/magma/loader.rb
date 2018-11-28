# Some vocabulary:
# A 'model' is the class representing a database table.
# A 'record' is an instance of a model or row in a database table.
# A 'template' is a json object describing a model.
# A 'document' is a json object describing a record.
# An 'entry' is a hash suitable for database loading prepared from a document.

class Magma
  class LoadFailed < Exception
    attr_reader :complaints

    def initialize(complaints)
      @complaints = complaints
    end
  end

  # A generic loader class.
  class Loader
    class << self
      def description desc=nil
        @description ||= desc
      end

      def arguments(args=nil)
        @arguments = args if args
        @arguments
      end

      def missing_arguments(user_arguments)
        @arguments ? @arguments.reject do |arg_name, arg_type|
          user_arguments.has_key?(arg_name)
        end.keys : []
      end

      def invalid_arguments(user_arguments)
        @arguments ? user_arguments.reject do |arg_name, argument|
          valid_argument?(arg_name, argument)
        end.keys : []
      end

      def file_argument?(arg_name)
        @arguments[arg_name.to_sym] == File
      end

      private

      def valid_argument?(arg_name, user_argument)
        arg_type = @arguments[arg_name]

        if arg_type == File
          return user_argument.has_key?(:tempfile) &&
            user_argument[:tempfile].is_a?(Tempfile)
        end

        case arg_type
        when nil
          return false
        when Class
          return user_argument.is_a?(arg_type)
        when Array
          return arg_type.any? {|type| user_argument.is_a?(type) }
        else
          return false
        end
      end

      public

      def loader_name
        module_name, loader_name = name.split(/::/)
        loader_name.snake_case.sub(/_loader$/,'').to_sym
      end

      def project_name
        module_name, loader_name = name.split(/::/)
        module_name.snake_case.to_sym
      end

      def list
        @descendants || []
      end

      def inherited(subclass)
        @descendants ||= []
        @descendants << subclass
      end
    end

    def initialize(project_name, arguments={})
      @project_name = project_name
      @arguments = arguments
      @records = {}
      @temp_id_counter = 0
      @validator = Magma::Validation.new
      @insert_count = 0
      @update_count = 0
    end

    attr_reader :insert_count, :update_count

    def push_record(model, document)
      records(model) << RecordEntry.new(model, document, records(model), self)
    end

    def attribute_entry(model, att_name, value)
      records(model).attribute_entry(att_name,value)
    end

    def identifier_id(model, identifier)
      records(model).identifier_id[identifier]
    end

    alias_method :identifier_exists?, :identifier_id

    def records(model)
      return @records[model] if @records[model]

      @records[model] = RecordSet.new(model, self)
      ensure_link_models(model)

      @records[model]
    end

    def validate(model, document)
      @validator.validate(model,document) do |error|
        yield error
      end
    end

    # Once we have loaded up all the records we wish to insert/update (upsert)
    # we run this function to kick off the DB insert and update queries.
    def dispatch_record_set
      find_complaints
      upsert
      update_temp_ids
      reset
    end

    def reset
      @records = {}
      @validator = Magma::Validation.new
      GC.start
    end

    # This lets you give an arbitrary object (e.g. a model used in the loader) a
    # temporary id so you can make database associations.
    def temp_id(obj)
      return nil if obj.nil?
      temp_ids[obj] ||= TempId.new(new_temp_id, obj)
    end

    private

    def find_complaints
      complaints = []

      @records.each do |model, record_set|
        next if record_set.empty?
        complaints.concat(record_set.map(&:complaints))
      end

      complaints.flatten!
      raise Magma::LoadFailed.new(complaints) unless complaints.empty?
    end

    # This 'upsert' function will look at the records and either insert or
    # update them as necessary.
    def upsert
      puts 'Attempting initial insert.'

      # Loop the records separate them into an insert group and an update group.
      # @records is separated out by model.
      @records.each do |model, record_set|

        # Skip if the record_set for this model is empty.
        next if record_set.empty?

        # Our insert and update record groupings.
        insert_records = record_set.select(&:valid_new_entry?)
        update_records = record_set.select(&:valid_update_entry?)

        # Update the insert and update stats.
        @insert_count += insert_records.count
        @update_count += update_records.count

        # Run the record insertion.
        insert_ids = model.multi_insert(
          insert_records.map(&:insert_entry),
          return: :primary_key
        )

        if insert_ids
          puts "Updating temp records with real ids for #{model}."
          insert_records.zip(insert_ids).each do |record, real_id|
            record.real_id = real_id
          end
        end

        # Run the record updates.
        update_records = update_records.map(&:update_entry)
        model.multi_update(records: update_records)
      end
    end

    def update_temp_ids
      @records.each do |model, record_set|
        next if record_set.empty?
        temp_records = record_set.select(&:valid_temp_update?)

        msg = "Found #{temp_records.count} records to "
        msg += "repair temp_ids for #{model}."
        puts msg

        args = {
          records: temp_records.map(&:temp_entry),
          src_id: :real_id,
          dest_id: :id
        }
        model.multi_update(args)
      end
    end

    def temp_ids
      @temp_ids ||= {}
    end

    def new_temp_id
      @temp_id_counter += 1
    end

    def ensure_link_models(model)
      model.attributes.each do |att_name, att|
        records(att.link_model) if att.is_a?(Magma::Link)
      end
    end
  end

end

require_relative './loader/base_attribute_entry'
require_relative './loader/record_entry'
require_relative './loader/record_set'
require_relative './loader/temp_id'
require_relative './loaders/tsv'
