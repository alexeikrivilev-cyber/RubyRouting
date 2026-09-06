# frozen_string_literal: true

require "digest"
require "json"
require "open3"

module RubyRouting
  module Case
    # Binds the bytes that were validated for submission to their input queue
    # and fixed organizer output paths. This is deliberately an operator guard,
    # not a deployment or persistence subsystem.
    class SubmissionManifest
      REQUIRED_OUTPUTS = {
        decisions: "routing_decisions_test.json",
        report: "routing_report_test.json"
      }.freeze

      attr_reader :root, :queue_path, :decisions_path, :report_path

      def self.build(root:, queue_path:, decisions_path:, report_path:)
        new(
          root: root,
          queue_path: queue_path,
          decisions_path: decisions_path,
          report_path: report_path
        ).tap(&:validate!)
      end

      def initialize(root:, queue_path:, decisions_path:, report_path:)
        @root = File.expand_path(root)
        @queue_path = File.expand_path(queue_path)
        @decisions_path = File.expand_path(decisions_path)
        @report_path = File.expand_path(report_path)
      end

      def validate!
        validate_output_path!(@decisions_path, :decisions)
        validate_output_path!(@report_path, :report)
        queue = queue_metadata
        decisions_digest = digest_file!(@decisions_path, "decisions artifact")
        report_digest = digest_file!(@report_path, "report artifact")
        ensure_trackable!(@decisions_path)
        ensure_trackable!(@report_path)

        @manifest = {
          queue_path: @queue_path,
          queue_sha256: queue.fetch(:sha256),
          operation_count: queue.fetch(:operation_count),
          first_operation_id: queue.fetch(:first_operation_id),
          last_operation_id: queue.fetch(:last_operation_id),
          decisions_path: @decisions_path,
          decisions_sha256: decisions_digest,
          report_path: @report_path,
          report_sha256: report_digest
        }.freeze
        freeze
        self
      end

      def verify!
        expected = @manifest || (raise OutputError, "submission manifest has not been validated")
        current = self.class.build(
          root: @root,
          queue_path: @queue_path,
          decisions_path: @decisions_path,
          report_path: @report_path
        ).to_h
        return self if current == expected

        raise OutputError, "submission artifacts changed after manifest validation"
      end

      # A manifest binds the bytes in the current worktree. Release-level
      # verification additionally has to prove that those same bytes are the
      # committed bytes of the exact checkout being released.
      def verify_committed!
        verify!
        {
          decisions: @decisions_path,
          report: @report_path
        }.each do |kind, path|
          relative = relative_path(path)
          stdout, stderr, status = Open3.capture3(
            "git", "-C", @root, "show", "HEAD:#{relative.tr(File::SEPARATOR, "/")}"
          )
          unless status.success?
            raise OutputError, "#{relative} is not present in Git HEAD: #{stderr.strip}"
          end
          expected_digest = @manifest.fetch(:"#{kind}_sha256")
          next if Digest::SHA256.hexdigest(stdout) == expected_digest

          raise OutputError, "#{relative} committed bytes differ from validated artifacts"
        end
        self
      end

      def to_h
        @manifest || (raise OutputError, "submission manifest has not been validated")
      end

      private

      def validate_output_path!(path, kind)
        expected = File.join(@root, REQUIRED_OUTPUTS.fetch(kind))
        return if path == expected && File.file?(path)

        raise OutputError, "#{kind} artifact must be the repository-root #{REQUIRED_OUTPUTS.fetch(kind)}"
      end

      def queue_metadata
        bytes = begin
          File.binread(@queue_path)
        rescue Errno::ENOENT => error
          raise InputError, "submission queue not found: #{error.message}"
        rescue SystemCallError => error
          raise InputError, "submission queue cannot be read: #{error.message}"
        end
        value = begin
          JSON.parse(bytes, create_additions: false, allow_duplicate_key: false)
        rescue JSON::ParserError => error
          raise InputError, "submission queue is invalid JSON: #{error.message}"
        end
        unless value.is_a?(Array)
          raise InputError, "submission queue root must be an Array"
        end

        ids = value.map do |operation|
          unless operation.is_a?(Hash) && operation["operation_id"].is_a?(String) && !operation["operation_id"].empty?
            raise InputError, "submission queue operations must have non-empty String operation_id"
          end
          operation.fetch("operation_id")
        end
        {
          sha256: Digest::SHA256.hexdigest(bytes),
          operation_count: ids.length,
          first_operation_id: ids.first,
          last_operation_id: ids.last
        }
      end

      def digest_file!(path, label)
        Digest::SHA256.file(path).hexdigest
      rescue Errno::ENOENT => error
        raise OutputError, "#{label} not found: #{error.message}"
      rescue SystemCallError => error
        raise OutputError, "#{label} cannot be read: #{error.message}"
      end

      def ensure_trackable!(path)
        relative = relative_path(path)
        _stdout, stderr, status = Open3.capture3(
          "git", "-C", @root, "check-ignore", "-q", "--", relative
        )
        raise OutputError, "#{relative} is ignored by Git" if status.success?
        return if status.exitstatus == 1

        raise OutputError, "cannot verify Git trackability for #{relative}: #{stderr.strip}"
      rescue Errno::ENOENT => error
        raise OutputError, "Git trackability check unavailable: #{error.message}"
      end

      def relative_path(path)
        path.delete_prefix("#{@root}#{File::SEPARATOR}")
      end
    end
  end
end
