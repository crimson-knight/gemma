require "spec"
require "webmock"

require "../src/gemma"
require "./support/*"

reset_storages

Spec.before_each do
  WebMock.reset
end
