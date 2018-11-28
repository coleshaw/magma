require_relative 'validation/model'

class Magma
  class Validation
    def initialize(options={})
      @models = {}
      @options = options
    end
    attr_reader :options

    def validate(model, document)
      model_validation(model).validate(document) do |error|
        yield error
      end
    end

    private

    def model_validation model
      @models[model] ||= Magma::Validation::Model.new(model, self)
    end
  end
end
