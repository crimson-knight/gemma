require "spectator"
require "webmock"

require "../src/*"
require "./support/file_helpers"
require "./support/gemma_helpers"
require "./support/have_permissions_matcher"

Spectator.configure do |config|
  config.randomize # Randomize test order.
end

Gemma.configure do |config|
  config.storages["cache"] = Gemma::Storage::Memory.new
  config.storages["store"] = Gemma::Storage::Memory.new
  config.storages["other_cache"] = Gemma::Storage::Memory.new
  config.storages["other_store"] = Gemma::Storage::Memory.new
end

Gemma.raise_if_missing_settings!

def clear_storages
  Gemma.settings.storages["cache"].as(Gemma::Storage::Memory).clear!
  Gemma.settings.storages["store"].as(Gemma::Storage::Memory).clear!
  Gemma.settings.storages["other_cache"].as(Gemma::Storage::Memory).clear!
  Gemma.settings.storages["other_store"].as(Gemma::Storage::Memory).clear!
end
