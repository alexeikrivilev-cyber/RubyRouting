# frozen_string_literal: true

require_relative "test_helper"

class AcceptanceTraceabilityTest < Minitest::Test
  def test_every_spec_acceptance_scenario_maps_to_an_executable_test_method
    expected_ids = (1..17).map { |number| format("AC-%03d", number) }
    assert_equal expected_ids, TestSupport::ACCEPTANCE_EVIDENCE.keys.sort

    TestSupport::ACCEPTANCE_EVIDENCE.each do |acceptance_id, references|
      refute_empty references, acceptance_id
      references.each do |reference|
        relative_path, method_name = reference.split("#", 2)
        path = File.expand_path("../#{relative_path}", __dir__)
        assert File.file?(path), "#{acceptance_id} points to missing test file #{relative_path}"
        source = File.read(path)
        assert_includes source, "def #{method_name}", "#{acceptance_id} points to missing test method #{reference}"
      end
    end
  end
end
