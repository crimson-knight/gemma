# Loads Grant on a SQLite file database for the specs that exercise
# `Gemma::Grant` against a real ORM, and defines the models they share.
require "./spec_helper"
require "sqlite3"
require "grant"
require "grant/adapter/sqlite"
require "../src/gemma/grant"

GRANT_SPEC_DATABASE_PATH = File.join(Dir.tempdir, "gemma-grant-spec-#{Process.pid}.db")

Grant::Connections << Grant::Adapter::Sqlite.new(name: "sqlite", url: "sqlite3://#{GRANT_SPEC_DATABASE_PATH}")

# The column type Gemma's Grant layer reads and writes.
alias AttachmentData = Gemma::UploadedFile

class IntegrationUser < Grant::Base
  connection sqlite
  table integration_users

  column id : Int64, primary: true
  column first_name : String?
  column avatar_data : AttachmentData?, converter: Grant::Converters::Json(AttachmentData, String), column_type: "TEXT"

  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  has_one_attached :avatar
end

class IntegrationPost < Grant::Base
  connection sqlite
  table integration_posts

  column id : Int64, primary: true
  column title : String?
  column images_data : Array(AttachmentData)?, converter: Grant::Converters::Json(Array(AttachmentData), String), column_type: "TEXT"

  include Gemma::Grant::Attachable

  has_many_attached :images
end

# An uploader that stores files under `test/`.
class PrefixedLocationUploader < Gemma
  def generate_location(metadata : Gemma::Metadata) : String
    File.join("test", super)
  end
end

class IntegrationDocument < Grant::Base
  connection sqlite
  table integration_documents

  column id : Int64, primary: true
  column file_data : AttachmentData?, converter: Grant::Converters::Json(AttachmentData, String), column_type: "TEXT"

  include Gemma::Grant::Attachable

  has_one_attached :file, uploader: PrefixedLocationUploader
end

# Two attachments with validators on each, from the persist probe.
class IntegrationProfile < Grant::Base
  connection sqlite
  table integration_profiles

  column id : Int64, primary: true
  column avatar_data : AttachmentData?, converter: Grant::Converters::Json(AttachmentData, String), column_type: "TEXT"
  column cover_data : AttachmentData?, converter: Grant::Converters::Json(AttachmentData, String), column_type: "TEXT"

  include Gemma::Grant::Attachable
  include Gemma::Grant::AttachmentValidators

  has_one_attached :avatar
  has_one_attached :cover

  validate_file_size_of :avatar, maximum: 3
  validate_content_type_of :cover, accept: ["image/*"]
end

GRANT_SPEC_SCHEMA = {
  "integration_users"     => "id INTEGER PRIMARY KEY, first_name TEXT, avatar_data TEXT",
  "integration_posts"     => "id INTEGER PRIMARY KEY, title TEXT, images_data TEXT",
  "integration_documents" => "id INTEGER PRIMARY KEY, file_data TEXT",
  "integration_profiles"  => "id INTEGER PRIMARY KEY, avatar_data TEXT, cover_data TEXT",
}

IntegrationUser.adapter.open do |database|
  GRANT_SPEC_SCHEMA.each do |table_name, columns|
    database.exec "DROP TABLE IF EXISTS #{table_name}"
    database.exec "CREATE TABLE #{table_name} (#{columns})"
  end
end

at_exit do
  {"", "-wal", "-shm"}.each { |suffix| File.delete?(GRANT_SPEC_DATABASE_PATH + suffix) }
end
