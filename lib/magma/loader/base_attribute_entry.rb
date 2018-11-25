class Magma
  class BaseAttributeEntry
    def initialize(model, attribute, loader)
      @model = model
      @attribute = attribute
      @loader = loader
    end

    def entry value
      nil
    end
  end
end
