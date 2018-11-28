class Magma
  class Validation
    class Links < Magma::Validation::Model
      def validate(document)
        return if @validator.options[:allow_invalid_links]
        @model.attributes.each do |attribute_name, attribute|
          next unless document.has_key?(attribute_name) && attribute.is_a?(Magma::Link)
          missing_identifier?(attribute.link_model, document[attribute_name]) do |value|
            yield "No such #{attribute_name} '#{value}'."
          end
        end
      end

      private

      def missing_identifier?(model, value)
        case value
        when Array
          value.each do |i|
            yield(i) unless model_identifiers(model)[i]
          end
        when Magma::TempId
          return
        else
          yield(value) unless model_identifiers(model)[value]
        end
      end

      def model_identifiers(model)
        @model_identifiers ||= {}
        @model_identifiers[model] ||= model.select_map( model.identity ).map do |identifier|
          [ identifier, true ]
        end.to_h
      end
    end
  end
end
