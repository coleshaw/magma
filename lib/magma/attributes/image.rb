class Magma
  class ImageAttribute < FileAttribute
    def json_payload(value)
      json = super

      json && json[:url] ?
        json.merge(
          thumb: Magma.instance.storage.download_url(@model.project_name, "thumb_#{value}")
        )
        : nil
    end
  end
end
