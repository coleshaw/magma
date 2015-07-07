class Magma
  class LoadFailed < Exception
    attr_reader :complaints
    def initialize complaints
      @complaints = complaints
    end
  end
  class RecordEntry
    def initialize klass, document
      @document = document
      @klass = klass
      @complaints = []
      @valid = true

      check_document_validity
    end

    attr_reader :complaints

    def valid_new_document 
      return nil unless valid?
      return nil if item_exists?
      @document
    end

    def valid_update_document
      return nil unless valid?
      return nil unless item_exists?
      return nil unless item_changed?
      update_fixes!
      @document
    end

    def valid?
      @valid
    end

    private
    def item_exists?
      @klass.identity && !@klass[@klass.identity => @document[@klass.identity]].nil?
    end

    def update_fixes!
      @document[:id] = item.id
      # never overwrite created_at
      @document.delete :created_at
    end

    def item
      @item ||= @klass[@klass.identity => @document[@klass.identity]]
    end

    def item_changed?
      @document.each do |att,value|
        if att =~ /_id$/
          old_value = item.send(att.to_s.sub(/_id$/,'').to_sym)
          old_value = old_value ? old_value.id : nil
        else
          old_value = item.send att.to_sym
        end
        if value.to_s != old_value.to_s
          return true
        end
      end
      nil
    end

    def check_document_validity
      if @klass.identity && !@document[@klass.identity]
        complain "Missing identifier for #{@klass.name}"
        @valid = false
        return
      end
      @document.each do |att,value|
        att = att.to_s.sub(/_id$/,'').to_sym
        if !@klass.attributes[att]
          complain "#{@klass.name} has no attribute '#{att}'"
          @valid = false
          next
        end
        @klass.attributes[att].validate(value) do |complaint|
          complain complaint
          @valid = false
        end
      end
    end

    def complain plaint
      @complaints << plaint
    end
  end
  class Loader
    # A generic loader class
    def initialize
      @records = {}
    end
    def push_record klass, document
      @records[klass] ||= []
      @records[klass] << RecordEntry.new(klass, document)
    end

    def dispatch_record_set
      @records.keys.each do |klass|
        complaints = @records[klass].map(&:complaints).flatten

        raise Magma::LoadFailed.new(complaints) unless complaints.empty?

        insert_records = @records[klass].map(&:valid_new_document).compact

        update_records = @records[klass].map(&:valid_update_document).compact

        # Now we have a list of valid records to insert for this class, let's create them:
        klass.multi_insert insert_records
        klass.multi_update update_records
      end
      @records = {}
    end
  end
end
