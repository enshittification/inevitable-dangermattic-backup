# frozen_string_literal: true

require_relative 'spec_helper'

module Danger
  describe Danger::TracksChecker do
    it 'is a plugin' do
      expect(described_class.new(nil)).to be_a Danger::Plugin
    end

    describe 'with Dangerfile' do
      before do
        @dangerfile = testing_dangerfile
        @plugin = @dangerfile.tracks_checker
      end

      let(:track_files) do
        [
          'AnalyticsTracker.kt',
          'AnalyticsEvent.kt',
          'LoginAnalyticsTracker.kt',
          'WooAnalyticsStat.swift'
        ]
      end

      let(:tracks_matchers) do
        [
          /AnalyticsTracker\.track/
        ]
      end

      describe '#check_tracks_changes' do
        before do
          allow(@plugin.git).to receive_messages(modified_files: [], added_files: [], deleted_files: [])

          stub_const('GitDiffStruct', Struct.new(:type, :path, :patch))
        end

        context 'when checking changes in Tracks-related files' do
          it 'reports a message with instructions for review when there are changes in Tracks-related files' do
            tracks_label = '[Tracks]'
            allow(@plugin.github).to receive(:pr_labels).and_return([tracks_label])
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(['Test.kt', 'LoginAnalyticsTracker.kt', 'Test.java'])

            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: tracks_label)

            expect(@dangerfile).to report_messages([TracksChecker::TRACKS_PR_INSTRUCTIONS + format(TracksChecker::TRACKS_NO_LABEL_INSTRUCTION_FORMAT, tracks_label)])
          end

          it 'reports a message with instructions for review without the label check when there are changes in Tracks-related files and no label parameter' do
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(['Test.kt', 'LoginAnalyticsTracker.kt', 'Test.java'])

            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: nil)

            expect(@dangerfile).to report_messages([TracksChecker::TRACKS_PR_INSTRUCTIONS])
          end

          it 'reports an error when there are changes in Tracks-related files but no Tracks label' do
            allow(@plugin.github).to receive(:pr_labels).and_return([])
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(['Test.kt', 'LoginAnalyticsTracker.kt', 'Test.java'])

            tracks_label = 'TRACKS'
            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: tracks_label)

            expect_label_checks(tracks_label)
          end

          it 'does nothing when there are no changes in Tracks-related files' do
            modified_files = ['MyClass.swift']
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(modified_files)
            allow(@plugin.git_utils).to receive(:matching_lines_in_diff_files).with(files: modified_files, line_matcher: kind_of(Proc), change_type: nil).and_return([])

            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: nil)

            expect(@dangerfile).to not_report
          end
        end

        context 'when checking Tracks-related changes within a diff' do
          it 'reports a message with instructions for review when there are matching changes' do
            tracks_label = 'Tracks'
            allow(@plugin.github).to receive(:pr_labels).and_return([tracks_label])
            modified_files = ['MyClass.kt']
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(modified_files)

            allow(@plugin.git_utils).to receive(:matching_lines_in_diff_files).with(files: modified_files, line_matcher: kind_of(Proc), change_type: nil) do |args|
              analytics_call_in_diff = '-                AnalyticsTracker.track("myEvent1")'
              expect(args[:line_matcher].call(analytics_call_in_diff)).to be true

              [analytics_call_in_diff]
            end

            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: tracks_label)

            expect(@dangerfile).to report_messages([TracksChecker::TRACKS_PR_INSTRUCTIONS + format(TracksChecker::TRACKS_NO_LABEL_INSTRUCTION_FORMAT, tracks_label)])
          end

          it 'reports a message with instructions without the label check for review when there are matching changes and no label parameter' do
            modified_files = ['MyClass.kt']
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(modified_files)

            allow(@plugin.git_utils).to receive(:matching_lines_in_diff_files).with(files: modified_files, line_matcher: kind_of(Proc), change_type: nil) do |args|
              analytics_call_in_diff = '-                AnalyticsTracker.track("evento")'
              expect(args[:line_matcher].call(analytics_call_in_diff)).to be true

              [analytics_call_in_diff]
            end

            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: nil)

            expect(@dangerfile).to report_messages([TracksChecker::TRACKS_PR_INSTRUCTIONS])
          end

          it 'reports a message with instructions for review and an error when there are matching changes and no label' do
            allow(@plugin.github).to receive(:pr_labels).and_return([])
            modified_files = ['MyClass.kt']
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(modified_files)

            allow(@plugin.git_utils).to receive(:matching_lines_in_diff_files).with(files: modified_files, line_matcher: kind_of(Proc), change_type: nil) do |args|
              analytics_call_in_diff = '-                AnalyticsTracker.track("myEvent1")'
              expect(args[:line_matcher].call(analytics_call_in_diff)).to be true

              [analytics_call_in_diff]
            end

            tracks_label = 'TRACKS PR'
            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: tracks_label)

            expect_label_checks(tracks_label)
          end

          it 'does nothing when there are no matching changes' do
            modified_files = ['MyClass.kt']
            allow(@plugin.git_utils).to receive(:all_changed_files).and_return(modified_files)

            allow(@plugin.git_utils).to receive(:matching_lines_in_diff_files).with(files: modified_files, line_matcher: kind_of(Proc), change_type: nil) do |args|
              analytics_call_in_diff = '+                AnalyticsHelper.log("event_1")'
              expect(args[:line_matcher].call(analytics_call_in_diff)).to be false

              []
            end

            @plugin.check_tracks_changes(tracks_files: track_files, tracks_usage_matchers: tracks_matchers, tracks_label: nil)

            expect(@dangerfile).to not_report
          end
        end
      end

      def expect_label_checks(tracks_label)
        expect(@dangerfile.status_report[:messages]).to eq [TracksChecker::TRACKS_PR_INSTRUCTIONS + format(TracksChecker::TRACKS_NO_LABEL_INSTRUCTION_FORMAT, tracks_label)]
        expect(@dangerfile.status_report[:errors]).to eq [format(TracksChecker::TRACKS_NO_LABEL_MESSAGE_FORMAT, tracks_label)]
      end
    end
  end
end
