# frozen_string_literal: true

require_relative 'utils/git_utils'

module Danger
  # Plugin to detect classes without Unit Tests in a PR.
  class AndroidUnitTestChecker < Plugin
    ANY_CLASS_DETECTOR = /class ([A-Z]\w+)\s*(.*?)\s*{/
    NON_PRIVATE_CLASS_DETECTOR = /(?:\s|public|internal|protected|final|abstract|static)*class ([A-Z]\w+)\s*(.*?)\s*{/

    DEFAULT_CLASSES_EXCEPTIONS = [
      /ViewHolder$/,
      /Module$/
    ].freeze

    DEFAULT_SUBCLASSES_EXCEPTIONS = [
      /(Fragment|Activity)\b/,
      /RecyclerView/
    ].freeze

    DEFAULT_UNIT_TESTS_BYPASS_PR_LABEL = 'unit-tests-exemption'

    # Check and warns about missing unit tests for a Git diff, with optional classes/subclasses to ignore and an
    # optional PR label to bypass the checks.
    #
    # @param classes_exceptions [Array<String>] Optional list of regexes matching class names to exclude from the
    # check.
    #   Defaults to DEFAULT_CLASSES_EXCEPTIONS.
    # @param subclasses_exceptions [Array<String>] Optional list of regexes matching base class names to exclude from
    # the check.
    #   Defaults to DEFAULT_SUBCLASSES_EXCEPTIONS.
    # @param bypass_label [String] Optional label to indicate we can bypass the check. Defaults to
    #   DEFAULT_UNIT_TESTS_BYPASS_PR_LABEL.
    # @return [void]
    #
    # @example Check missing unit tests
    #   check_missing_tests()
    #
    # @example Check missing unit tests excluding certain classes and subclasses
    #   check_missing_tests(classes_exceptions: [/ViewHolder$/], subclasses_exceptions: [/RecyclerView/])
    #
    # @example Check missing unit tests with a custom bypass label
    #   check_missing_tests(bypass_label: 'BypassTestCheck')
    def check_missing_tests(classes_exceptions: DEFAULT_CLASSES_EXCEPTIONS, subclasses_exceptions: DEFAULT_SUBCLASSES_EXCEPTIONS,
                            bypass_label: DEFAULT_UNIT_TESTS_BYPASS_PR_LABEL)
      list = find_classes_missing_tests(
        git.diff,
        classes_exceptions,
        subclasses_exceptions
      )

      return if list.empty?

      if danger.github.pr_labels.include?(bypass_label)
        list.each do |c|
          warn("Class `#{c.classname}` is missing tests, but `#{bypass_label}` label was set to ignore this.")
        end
      else
        list.each do |c|
          failure("Please add tests for class `#{c.classname}` (or add `#{bypass_label}` label to ignore this).")
        end
      end
    end

    private

    ClassViolation = Struct.new(:classname, :file)

    # @param [Git::Diff] the git diff object
    # @param [Array<String>] Regexes matching class names to exclude from the check.
    # @param [Array<String>] Regexes matching base class names to exclude from the check
    # @return [Array<ClassViolation>] An array of `ClassViolation` objects for each added class that is missing a test
    def find_classes_missing_tests(git_diff, classes_exceptions, subclasses_exceptions)
      violations = []
      removed_classes = []
      added_test_lines = []

      # Parse the diff of each file, storing test lines for test files, and added/removed classes for non-test files
      git_diff.each do |file_diff|
        file_path = file_diff.path
        if test_file?(path: file_path)
          # Store added test lines from test files
          added_test_lines += file_diff.patch.each_line.select do |line|
            GitUtils.change_type(diff_line: line) == :added
          end
        else
          # Detect added and removed classes in non-test files
          file_diff.patch.each_line do |line|
            case GitUtils.change_type(diff_line: line)
            when :added
              matches = line.scan(NON_PRIVATE_CLASS_DETECTOR)
              matches.reject! do |m|
                class_match_is_exception?(
                  m,
                  file_path,
                  classes_exceptions,
                  subclasses_exceptions
                )
              end
              violations += matches.map { |m| ClassViolation.new(m[0], file_path) }
            when :removed
              matches = line.scan(ANY_CLASS_DETECTOR)
              removed_classes += matches.map { |m| m[0] }
            end
          end
        end
      end

      # We only want newly added classes, not if class signature was modified or line was moved
      violations.reject! { |v| removed_classes.include?(v.classname) }

      # For each remaining candidate, only keep the ones _not_ used in a new test.
      # The regex will match usages of this class in any test file
      violations.select { |v| added_test_lines.none? { |line| line =~ /\b#{v.classname}\b/ } }
    end

    # @param [Array<String>] match an array of captured substrings matching our `*_CLASS_DETECTOR` for a given line
    # @param [String] file the path to the file where that class declaration line was matched
    # @param [Array<String>] Regexes matching class names to exclude from the check.
    # @param [Array<String>] Regexes matching base class names to exclude from the check
    # @return [void]
    def class_match_is_exception?(match, file, classes_exceptions, subclasses_exceptions)
      return true if classes_exceptions.any? { |re| match[0] =~ re }

      subclass_regexp = File.extname(file) == '.java' ? /extends ([A-Z]\w+)/ : /\s*:\s*([A-Z]\w+)/
      subclass = match[1].match(subclass_regexp)&.captures&.first
      subclasses_exceptions.any? { |re| subclass =~ re }
    end

    def test_file?(path:)
      path.match? %r{/(test|androidTest).*\.(java|kt)$}
    end
  end
end
