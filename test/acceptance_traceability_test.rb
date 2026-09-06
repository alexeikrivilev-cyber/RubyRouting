# frozen_string_literal: true

require_relative "test_helper"

class AcceptanceTraceabilityTest < Minitest::Test
  def test_every_spec_acceptance_scenario_maps_to_an_executable_test_method
    expected_ids = (1..17).map { |number| format("AC-%03d", number) } + ["PTZ-001", "PTZ-002", "PTZ-003", "PTZ-004", "PTZ-005", "PTZ-101", "PTZ-102", "PTZ-103", "PTZ-104", "PTZ-105", "PTZ-106", "PTZ-107", "PTZ2-001", "PTZ2-002", "PTZ2-003", "PTZ2-004", "PTZ2-005", "PTZ2-101", "PTZ2-102", "PTZ2-103", "PTZ2-104", "PTZ2-105", "PTZ2-106", "PTZ2-107", "PTZ2-108", "PTZ2-109", "PTZ2-110"]
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
