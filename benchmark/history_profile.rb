# frozen_string_literal: true

require "objspace"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby_routing"

module RubyRouting
  module Benchmarking
    module HistoryProfile
      SAMPLE_SIZES = [100, 250, 500].freeze

      class SuccessProvider
        def initiate(request)
          RubyRouting::ProviderObservation.new(
            observation_id: "history-profile:#{request.operation_id}",
            payout_id: request.payout_id,
            provider_id: request.provider_id,
            operation_id: request.operation_id,
            attempt_id: request.attempt_id,
            outcome: RubyRouting::NormalizedOutcome.success(attribution: :provider)
          )
        end

        def resolve(_request)
          raise NotImplementedError, "history profile only exercises immediate initiation"
        end
      end

      module_function

      def run(payout_count:)
        unless payout_count.is_a?(Integer) && payout_count.positive?
          raise ArgumentError, "payout_count must be a positive Integer"
        end

        policy, coordinator, app = build_application

        GC.start
        before_bytes = ObjectSpace.memsize_of_all
        before_slots = GC.stat.fetch(:heap_live_slots)
        lifecycle_started_at = monotonic_now

        payout_count.times do |index|
          result = app.submit(
            intent: RubyRouting::PayoutIntent.new(
              id: "history-profile-#{index}",
              money: RubyRouting::Money.new(100, "RUB")
            ),
            policy: policy
          )
          unless result.status == :success
            raise "history profile payout #{index} did not settle: #{result.status}"
          end
        end

        lifecycle_seconds = monotonic_now - lifecycle_started_at
        facts = coordinator.facts
        GC.start
        after_bytes = ObjectSpace.memsize_of_all
        after_slots = GC.stat.fetch(:heap_live_slots)

        analytics_seconds, analytics = timed do
          RubyRouting::Projections::Analytics.from_facts(facts)
        end
        restore_seconds, restored = timed do
          RubyRouting::State::Coordinator.from_facts(facts: facts)
        end
        audit_queries = RubyRouting::Application::Queries.new(
          coordinator: coordinator,
          policy_registry: RubyRouting::PolicyRegistry.new
        )
        audit_page_seconds, audit_page = timed do
          100.times do
            audit_queries.audit_facts_page(offset: 0, limit: 256)
          end
          audit_queries.audit_facts_page(offset: 0, limit: 256)
        end
        audit_filtered_page_seconds, audit_filtered_page = timed do
          100.times do
            audit_queries.audit_facts_page(
              payout_id: "history-profile-#{payout_count - 1}",
              type: :provider_observed,
              offset: 0,
              limit: 256
            )
          end
          audit_queries.audit_facts_page(
            payout_id: "history-profile-#{payout_count - 1}",
            type: :provider_observed,
            offset: 0,
            limit: 256
          )
        end
        unless restored.facts.map(&:payload) == facts.map(&:payload)
          raise "history profile restore changed durable fact payloads"
        end
        unless analytics.eventual_success_count == payout_count
          raise "history profile analytics count mismatch: #{analytics.eventual_success_count}"
        end
        unless audit_page.total == facts.length && audit_page.facts.length == [256, facts.length].min
          raise "history profile audit page mismatch"
        end
        unless audit_filtered_page.total == 1 && audit_filtered_page.facts.length == 1
          raise "history profile filtered audit page mismatch"
        end

        {
          payout_count: payout_count,
          fact_count: facts.length,
          facts_per_payout: Rational(facts.length, payout_count),
          lifecycle_seconds: lifecycle_seconds,
          analytics_seconds: analytics_seconds,
          restore_seconds: restore_seconds,
          audit_page_seconds: audit_page_seconds,
          audit_filtered_page_seconds: audit_filtered_page_seconds,
          heap_memsize_delta_bytes: after_bytes - before_bytes,
          heap_live_slot_delta: after_slots - before_slots
        }.freeze
      end

      def run_concurrent(payout_count:, worker_count:)
        unless payout_count.is_a?(Integer) && payout_count.positive?
          raise ArgumentError, "payout_count must be a positive Integer"
        end
        unless worker_count.is_a?(Integer) && worker_count.positive?
          raise ArgumentError, "worker_count must be a positive Integer"
        end

        policy, coordinator, app = build_application
        errors = Queue.new
        started_at = monotonic_now
        workers = worker_count.times.map do |worker_index|
          Thread.new do
            worker_index.step(payout_count - 1, worker_count) do |index|
              result = app.submit(
                intent: RubyRouting::PayoutIntent.new(
                  id: "history-profile-concurrent-#{index}",
                  money: RubyRouting::Money.new(100, "RUB")
                ),
                policy: policy
              )
              unless result.status == :success
                raise "concurrent payout #{index} did not settle: #{result.status}"
              end
            rescue StandardError => error
              errors << [index, error]
            end
          end
        end
        workers.each(&:join)
        unless errors.empty?
          index, error = errors.pop
          raise "concurrent history profile payout #{index} failed: #{error.message}"
        end

        elapsed = monotonic_now - started_at
        facts = coordinator.facts
        analytics = RubyRouting::Projections::Analytics.from_facts(facts)
        unless analytics.eventual_success_count == payout_count
          raise "concurrent history profile analytics count mismatch: #{analytics.eventual_success_count}"
        end

        {
          payout_count: payout_count,
          worker_count: worker_count,
          fact_count: facts.length,
          lifecycle_seconds: elapsed,
          throughput_per_second: payout_count / elapsed
        }.freeze
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
      private_class_method :monotonic_now

      def build_application
        policy = RubyRouting::RoutingPolicy.new(
          id: "history-profile-policy",
          epoch: "20260831",
          measure: :count,
          targets: { "A" => 1, "B" => 1 }
        )
        coordinator = RubyRouting::State::Coordinator.new(
          opportunities: %w[A B].map do |provider_id|
            RubyRouting::ProviderOpportunity.new(provider_id: provider_id)
          end
        )
        provider = SuccessProvider.new
        app = RubyRouting::Application::Orchestrator.new(
          coordinator: coordinator,
          providers: { "A" => provider, "B" => provider }
        )
        [policy, coordinator, app]
      end
      private_class_method :build_application

      def timed
        started_at = monotonic_now
        result = yield
        [monotonic_now - started_at, result]
      end
      private_class_method :timed
    end
  end
end

if $PROGRAM_NAME == __FILE__
  puts "Ruby: #{RUBY_DESCRIPTION}"
  puts "YJIT: #{!!(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?)}"
  puts "History profile: bounded 100/250/500 payout samples; not a 100k campaign"
  puts "payouts facts facts/payout lifecycle_s analytics_s restore_s audit_page_s audit_filtered_s heap_bytes slots"
  RubyRouting::Benchmarking::HistoryProfile::SAMPLE_SIZES.each do |payout_count|
    row = RubyRouting::Benchmarking::HistoryProfile.run(payout_count: payout_count)
    puts format(
      "%7d %5d %11s %11.4f %11.4f %10.4f %13.4f %17.4f %11d %6d",
      row.fetch(:payout_count),
      row.fetch(:fact_count),
      row.fetch(:facts_per_payout),
      row.fetch(:lifecycle_seconds),
      row.fetch(:analytics_seconds),
      row.fetch(:restore_seconds),
      row.fetch(:audit_page_seconds),
      row.fetch(:audit_filtered_page_seconds),
      row.fetch(:heap_memsize_delta_bytes),
      row.fetch(:heap_live_slot_delta)
    )
  end
  concurrent = RubyRouting::Benchmarking::HistoryProfile.run_concurrent(
    payout_count: 500,
    worker_count: 4
  )
  puts format(
    "concurrent %d payouts/%d workers facts=%d lifecycle=%.4f s throughput=%.1f ops/s",
    concurrent.fetch(:payout_count),
    concurrent.fetch(:worker_count),
    concurrent.fetch(:fact_count),
    concurrent.fetch(:lifecycle_seconds),
    concurrent.fetch(:throughput_per_second)
  )
end
