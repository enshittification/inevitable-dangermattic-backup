# frozen_string_literal: true

module Danger
  # Plugin for checking labels associated with a pull request.
  #
  # @example Checking for specific labels and generating warnings/errors:
  #   labels_checker.check(
  #     do_not_merge_labels: ['Do Not Merge'],
  #     required_labels: ['Bug', 'Enhancement'],
  #     required_labels_error: 'Please ensure the PR has labels "Bug" or "Enhancement".',
  #     recommended_labels: ['Documentation'],
  #     recommended_labels_warning: 'Consider adding the "Documentation" label for better tracking.'
  #   )
  #
  # @see Automattic/dangermattic
  # @tags github, process
  #
  class LabelsChecker < Plugin
    # Checks if a PR is missing labels or is marked with labels for not merging.
    # If recommended labels are missing, the plugin will emit a warning. If a required label is missing, or the PR
    # has a label indicating that the PR should not be merged, an error will be emitted, preventing the final merge.
    #
    # @param do_not_merge_labels [Array<String>] The possible labels indicating that a merge should not be allowed.
    # @param required_labels [Array<Regexp>] The list of Regular Expressions describing all the type of labels that are *required* on PR (e.g. `[/^feature:/, `/^type:/]` or `bug|bugfix-exemption`).
    #   Defaults to an empty array if not provided.
    # @param required_labels_error [String] The error message displayed if the required labels are not present.
    #   Defaults to a generic message that includes the missing label's regexes.
    # @param recommended_labels [Array<Regexp>] The list of Regular Expressions describing all the type of labels that we want a PR to have,
    # with a warning if it doesn't (e.g. `[/^feature:/, `/^type:/]` or `bug|bugfix-exemption`).
    #   Defaults to an empty array if not provided.
    # @param recommended_labels_warning [String] The warning message displayed if the recommended labels are not present.
    #   Defaults to a generic message that includes the missing label's regexes.
    #
    # @note Tip: if you want to require or recommend "at least one label", you can use
    #  an array of a single empty regex `[//]` to match "a label with any name".
    #
    # @return [void]
    def check(do_not_merge_labels: [], required_labels: [], required_labels_error: nil, recommended_labels: [], recommended_labels_warning: nil)
      github_labels = danger.github.pr_labels

      # A PR shouldn't be merged with the 'DO NOT MERGE' label
      found_do_not_merge_labels = github_labels.select do |github_label|
        do_not_merge_labels&.any? { |label| github_label.casecmp?(label) }
      end

      failure("This PR is tagged with #{markdown_list_string(found_do_not_merge_labels)} label(s).") unless found_do_not_merge_labels.empty?

      # fail if a PR is missing any of the required labels
      check_missing_labels(labels: github_labels, expected_labels: required_labels, report_on_missing: :error, custom_message: required_labels_error)

      # warn if a PR is missing any of the recommended labels
      check_missing_labels(labels: github_labels, expected_labels: recommended_labels, report_on_missing: :warning, custom_message: recommended_labels_warning)
    end

    private

    def check_missing_labels(labels:, expected_labels:, report_on_missing:, custom_message: nil)
      missing_expected_labels = expected_labels.reject do |required_label|
        labels.any? { |label| label =~ required_label }
      end

      return if missing_expected_labels.empty?

      missing_labels_list = missing_expected_labels.map(&:source)
      message = custom_message || "PR is missing label(s) matching: #{markdown_list_string(missing_labels_list)}"

      reporter.report(message: message, type: report_on_missing)
    end

    def markdown_list_string(items)
      items.map { |item| "`#{item}`" }.join(', ')
    end
  end
end
