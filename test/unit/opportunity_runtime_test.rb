# frozen_string_literal: true

require_relative "../test_helper"

class OpportunityRuntimeTest < Minitest::Test
  def test_materialization_composes_dynamic_evidence_with_static_hard_gates
    dynamic_only = RubyRouting::Routing::OpportunityRuntime.materialize(
      opportunity: RubyRouting::ProviderOpportunity.new(provider_id: "A"),
      available_provider_ids: ["A"],
      capacity_available: false,
      health_available: true,
      throughput_available: true
    )

    assert_equal true, dynamic_only.available
    assert_equal false, dynamic_only.capacity_available
    assert_equal true, dynamic_only.health_available
    assert_equal true, dynamic_only.throughput_available

    opportunity = RubyRouting::ProviderOpportunity.new(
      provider_id: "A",
      available: true,
      capacity_available: false,
      health_available: true,
      throughput_available: false
    )

    runtime = RubyRouting::Routing::OpportunityRuntime.materialize(
      opportunity: opportunity,
      available_provider_ids: ["B"],
      capacity_available: true,
      health_available: false,
      throughput_available: true
    )

    assert_equal false, runtime.available
    assert_equal false, runtime.capacity_available
    assert_equal false, runtime.health_available
    assert_equal false, runtime.throughput_available
    assert_equal true, opportunity.available
    assert_equal false, opportunity.capacity_available
  end
end
