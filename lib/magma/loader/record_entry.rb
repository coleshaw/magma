class Magma
  class RecordEntry
    attr_reader :complaints
    attr_accessor :real_id

    def initialize(model, document, set, loader)
      @document = document
      @model = model
      @set = set
      @loader = loader
      @complaints = []
      @valid = true

      check_document_validity
    end

    def valid_new_entry?
      valid? && !record_exists?
    end

    def valid_update_entry?
      valid? && record_exists?
    end

    def valid_temp_update?
      valid? && needs_temp?
    end

    def valid?
      @valid
    end

    def needs_temp?
      @needs_temp
    end

    def insert_entry
      Hash[
        @document.map do |att_name,value|
          # filter out temp ids
          if att_name == :temp_id
            value.record_entry = self
            next
          end
          if value.is_a? Magma::TempId
            @needs_temp = true
            next
          end
          @loader.attribute_entry(@model, att_name, value)
        end.compact
      ]
    end

    def update_entry
      entry = insert_entry
      entry[:id] = @loader.identifier_id(@model, @document[@model.identity])

      # Never overwrite created_at.
      entry.delete(:created_at)
      entry
    end

    def temp_entry
      entry = @document.clone

      # Replace the entry with the appropriate values for the column.
      Hash[
        entry.map do |att_name,value|
          if att_name == :temp_id
            [ :real_id, value.real_id ]
          elsif value.is_a? Magma::TempId
            @loader.attribute_entry(@model, att_name, value)
          else
            nil
          end
        end.compact
      ]
    end

    private

    def record_exists?
      @model.has_identifier? && @loader.identifier_exists?(@model,@document[@model.identity])
    end

    def check_document_validity
      @set.validate(@document) do |complaint|
        complain complaint
        @valid = false
      end
    end

    def complain plaint
      @complaints << plaint
    end
  end
end
