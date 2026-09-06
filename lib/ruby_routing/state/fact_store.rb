# frozen_string_literal: true

module RubyRouting
  module State
    # Owns append-only fact identity and delivery while the coordinator owns
    # synchronization and the mutable projections built from those facts.
    class FactStore
      def initialize(journal: nil, facts: nil)
        @journal = journal
        source = facts || (journal.respond_to?(:facts) ? journal.facts : [])
        normalized_source = RubyRouting::Collection.to_array(source, "facts")
        validate_facts!(normalized_source)
        if facts && journal.respond_to?(:facts) && !same_facts?(normalized_source, journal.facts)
          raise RubyRouting::State::DurableCorruptionError,
            "provided facts do not match durable journal history"
        end

        @facts = normalized_source.dup
        @sequence = @facts.last&.sequence || 0
        @pending = nil
        @journal_unusable = false
      end

      def revision
        @sequence + (@pending ? @pending.length : 0)
      end

      def append(type:, payout_id:, payload: {})
        next_sequence = @sequence + (@pending ? @pending.length : 0) + 1
        fact = RubyRouting::Fact.new(
          sequence: next_sequence,
          type: type,
          fact_id: "fact:#{next_sequence}",
          payout_id: payout_id,
          payload: payload
        )
        if @pending
          @pending << fact
        else
          append_to_journal([fact])
          publish([fact])
        end
        fact
      end

      # Stage a coordinator mutation so its facts reach durable storage as one
      # logical append. A non-local return from the caller is treated as a
      # successful mutation when it produced pending facts; an exception drops
      # all staged facts and lets the coordinator restore its mutable state.
      def transaction
        raise ArgumentError, "fact store transaction is already active" if @pending

        @pending = []
        committed = false
        begin
          result = yield
          commit_pending!
          committed = true
          result
        ensure
          unless committed
            if $!.nil? && @pending&.any?
              commit_pending!
            else
              @pending = nil
            end
          end
        end
      end

      def transaction_active?
        !@pending.nil?
      end

      def durable?
        !@journal.nil?
      end

      def facts
        (@facts + (@pending || [])).dup.freeze
      end

      private

      def validate_facts!(facts)
        facts.each_with_index do |fact, index|
          unless fact.is_a?(RubyRouting::Fact)
            raise ArgumentError, "facts must contain RubyRouting::Fact values"
          end

          expected_sequence = index + 1
          unless fact.sequence == expected_sequence && fact.fact_id == "fact:#{expected_sequence}"
            raise RubyRouting::State::DurableCorruptionError,
              "fact sequence discontinuity at #{expected_sequence}"
          end
        end
      end

      def same_facts?(left, right)
        normalized_right = RubyRouting::Collection.to_array(right, "facts")
        return false unless left.length == normalized_right.length

        left.zip(normalized_right).all? do |expected, actual|
          fact_signature(expected) == fact_signature(actual)
        end
      rescue StandardError
        false
      end

      def commit_pending!
        pending = @pending || []
        if pending.empty?
          @pending = nil
          return
        end

        if @journal
          append_to_journal(pending)
        end
        publish(pending)
        @pending = nil
      end

      def publish(facts)
        @facts.concat(facts)
        @sequence = @facts.last&.sequence || 0
      end

      def append_to_journal(facts)
        return unless @journal
        if @journal_unusable
          raise RubyRouting::State::DurableCorruptionError,
            "durable journal is unusable after an ambiguous append failure"
        end

        begin
          if @journal.respond_to?(:append_many)
            @journal.append_many(facts)
          else
            facts.each { |fact| @journal.append(fact) }
          end
        rescue StandardError => error
          # A journal may fail after its write has become visible (for
          # example, after fsync but before returning). Treating that as an
          # uncommitted mutation would let the next mutation reuse identities
          # already present on disk. Reconcile the exact expected prefix/suffix
          # before deciding that the durable append really failed.
          case journal_append_state(facts)
          when :complete
            nil
          when :unchanged
            raise error
          # If the journal cannot expose a durable fact view, there is no
          # safe way to distinguish a pre-write failure from a partial write.
          # Fail closed so a later append cannot reuse identities against an
          # unobserved durable suffix.
          when :unknown
            @journal_unusable = true
            poison_journal!("append outcome could not be established: #{error.message}")
            raise RubyRouting::State::DurableCorruptionError,
              "durable append outcome is unknown; journal is unusable: #{error.message}"
          when :corrupt
            @journal_unusable = true
            poison_journal!("append failure left a non-prefix durable history")
            raise RubyRouting::State::DurableCorruptionError,
              "durable journal became unusable after an ambiguous append failure: #{error.message}"
          end
        end
      end

      def journal_append_state(facts)
        return :unknown unless @journal.respond_to?(:facts)

        durable_facts = @journal.facts
        expected_facts = @facts + facts
        return :complete if same_facts?(durable_facts, expected_facts)
        return :unchanged if same_facts?(durable_facts, @facts)

        :corrupt
      rescue RubyRouting::State::DurableCorruptionError
        :corrupt
      rescue StandardError
        :unknown
      end

      def poison_journal!(reason)
        return unless @journal.respond_to?(:poison!)

        @journal.poison!(reason)
      rescue StandardError
        # Poisoning is a secondary containment hook. Its failure must not mask
        # the primary durable-corruption contract or make the store appear
        # retryable; @journal_unusable has already been set by the caller.
        nil
      end

      def fact_signature(fact)
        [fact.sequence, fact.type, fact.fact_id, fact.payout_id, fact.payload]
      end
    end
  end
end
