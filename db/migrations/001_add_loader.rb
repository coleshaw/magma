Sequel.migration do
  change do
    create_table(:load_requests) do
      primary_key :id
      DateTime :created_at, :null=>false
      DateTime :updated_at, :null=>false
      String :project_name, null: false
      String :user, null: false
      String :loader, null: false
      String :status, null: false
      String :message, null: false
      json :arguments, null: false
    end
  end
end
