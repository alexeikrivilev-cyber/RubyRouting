# frozen_string_literal: true

require_relative "test_helper"

class AcceptanceTraceabilityTest < Minitest::Test
  def test_every_spec_acceptance_scenario_maps_to_an_executable_test_method
    expected_ids = (1..17).map { |number| format("AC-%03d", number) } + ["PTZ-001", "PTZ-002", "PTZ-003", "PTZ-004", "PTZ-005", "PTZ-101", "PTZ-102", "PTZ-103", "PTZ-104", "PTZ-105", "PTZ-106", "PTZ-107", "PTZ2-001", "PTZ2-002", "PTZ2-003", "PTZ2-004", "PTZ2-005", "PTZ2-101", "PTZ2-102", "PTZ2-103", "PTZ2-104", "PTZ2-105", "PTZ2-106", "PTZ2-107", "PTZ2-108", "PTZ2-109", "PTZ2-110", "PTZ3-001", "PTZ3-002", "PTZ3-003", "PTZ3-004", "PTZ3-005", "PTZ3-101", "PTZ3-102", "PTZ3-103", "PTZ3-104", "PTZ3-105", "PTZ3-106", "PTZ3-107", "PTZ3-108", "PTZ3-109", "PTZ3-111", "PTZ3-112", "PTZ3-113", "PTZ3-114", "PTZ3-115", "PTZ3-116", "PTZ3-117", "PTZ3-118", "PTZ3-119", "PTZ3-120", "PTZ3-121", "PTZ3-122", "PTZ3-123", "PTZ3-124", "PTZ3-125", "PTZ3-126", "PTZ3-127", "PTZ3-128", "PTZ3-129", "PTZ3-130", "PTZ3-131", "PTZ3-132", "PTZ3-133", "PTZ3-134", "PTZ3-135", "PTZ3-136", "PTZ3-137", "PTZ3-138", "PTZ3-139", "PTZ3-140", "PTZ3-141", "PTZ3-142", "PTZ3-143", "PTZ3-144", "PTZ3-145", "PTZ3-146", "PTZ3-147", "PTZ3-148", "PTZ3-149"]
    expected_ids.concat(["PTZ3-150", "PTZ3-151", "PTZ3-152", "PTZ3-153", "PTZ3-154", "PTZ3-155", "PTZ4-001", "PTZ4-002", "PTZ4-003", "PTZ4-004", "PTZ4-101", "PTZ4-102", "PTZ4-103", "PTZ4-104"])
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
