# frozen_string_literal: true

module Danger
  # Plugin to check the size of a Pull Request content and text body.
  #
  # @example Running a PR diff size check with default parameters
  #
  #          # Check the total size of changes in the PR using the default parameters, reporting a warning if the PR is larger than 500
  #          pr_size_checker.check_diff_size(max_size: 500)
  #
  # @example Running a PR diff size check customizing the size, message and type of report
  #
  #          # Check the total size of changes in the PR, reporting an error if the diff is larger than 1000 using the specified message
  #          pr_size_checker.check_diff_size(max_size: 1000, message: 'PR too large, 1000 is the max!!', report_type: :error)
  #
  # @example Running a PR diff size check on the specified files in part of the diff
  #
  #          # Check the size of insertions in the files selected by the file_selector
  #          pr_size_checker.check_diff_size(file_selector: ->(file) { file.include?('/java/test/') }, type: :insertions)
  #
  # @example Running a PR description length check
  #
  #          # Check the PR Body using the default parameters, reporting a warning if the PR is smaller than 10 characters
  #          pr_size_checker.check_pr_body(min_length: 10)
  #
  # @example Running a PR description length check with custom parameters
  #
  #          # Check if the minimum length of the PR body is smaller than 20 characters, reporting an error using a custom error message
  #          pr_size_checker.check_pr_body(min_length: 20, message: 'Add a better description, 20 chars at least!!', report_type: :error)
  #
  # @see Automattic/dangermattic
  # @tags github, pull request, process
  #
  class PRSizeChecker < Plugin
    DEFAULT_DIFF_SIZE_MESSAGE_FORMAT = 'This PR is larger than %d lines of changes. Please consider splitting it into smaller PRs for easier and faster reviews.'
    DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT = 'The PR description appears very short, less than %d characters long. Please provide a summary of your changes in the PR description.'

    # Check the size of the PR diff against a specified maximum size.
    #
    # @param max_size [Integer] The maximum allowed size for the diff.
    # @param file_selector [Proc] Optional closure to filter the files in the diff to be used for size calculation.
    # @param type [:insertions, :deletions, :all] The type of diff size to check. (default: :all)
    # @param message [String] The message to display if the diff size exceeds the maximum. (default: DEFAULT_DIFF_SIZE_MESSAGE)
    # @param report_type [Symbol] (optional) The type of report for the message. Types: :error, :warning (default), :message.
    #
    # @return [void]
    def check_diff_size(max_size:, file_selector: nil, type: :all, message: format(DEFAULT_DIFF_SIZE_MESSAGE_FORMAT, max_size), report_type: :warning)
      case type
      when :insertions
        reporter.report(message: message, type: report_type) if insertions_size(file_selector: file_selector) > max_size
      when :deletions
        reporter.report(message: message, type: report_type) if deletions_size(file_selector: file_selector) > max_size
      when :all
        reporter.report(message: message, type: report_type) if diff_size(file_selector: file_selector) > max_size
      end
    end

    # Check the size of the Pull Request description (PR body) against a specified minimum size.
    #
    # @param min_length [Integer] The minimum allowed length for the PR body.
    # @param message [String] The message to display if the length of the PR body is smaller than the minimum. (default: DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT)
    # @param report_type [Boolean] If true, fail the PR check when the PR body length is too small. (default: false)
    #
    # @return [void]
    def check_pr_body(min_length:, message: format(DEFAULT_MIN_PR_BODY_MESSAGE_FORMAT, min_length), report_type: :warning)
      return if danger.github.pr_body.length > min_length

      reporter.report(message: message, type: report_type)
    end

    # Calculate the total size of insertions in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the insertions calculation.
    #
    # @return [Integer] The total size of insertions in the selected modified files.
    def insertions_size(file_selector: nil)
      return danger.git.insertions unless file_selector

      filtered_files = git_utils.all_changed_files.select(&file_selector)

      filtered_files.sum do |file|
        # stats for a file in the GitHub API might be nil, making `info_for_file()` crash
        next 0 if danger.git.diff.stats[:files][file].nil?

        danger.git.info_for_file(file)&.[](:insertions).to_i
      end
    end

    # Calculate the total size of deletions in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the deletions calculation.
    #
    # @return [Integer] The total size of deletions in the selected modified files.
    def deletions_size(file_selector: nil)
      return danger.git.deletions unless file_selector

      filtered_files = git_utils.all_changed_files.select(&file_selector)

      filtered_files.sum do |file|
        # stats for a file in the GitHub API might be nil, making `info_for_file()` crash
        next 0 if danger.git.diff.stats[:files][file].nil?

        danger.git.info_for_file(file)&.[](:deletions).to_i
      end
    end

    # Calculate the total size of changes (insertions and deletions) in modified files that match the file selector.
    #
    # @param file_selector [Proc] Select the files to be used for the total insertions and deletions calculation.
    #
    # @return [Integer] The total size of changes in the selected modified files.
    def diff_size(file_selector: nil)
      return danger.git.lines_of_code unless file_selector

      filtered_files = git_utils.all_changed_files.select(&file_selector)

      filtered_files.sum do |file|
        # stats for a file in the GitHub API might be nil, making `info_for_file()` crash
        next 0 if danger.git.diff.stats[:files][file].nil?

        danger.git.info_for_file(file)&.[](:deletions).to_i + danger.git.info_for_file(file)&.[](:insertions).to_i
      end
    end
  end
end
