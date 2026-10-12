# frozen_string_literal: true

require File.expand_path('../test_helper', __dir__)

# A converter command runs within the time limit of its conversion (Jan,
# 2026-10-12, round 5, port of curecodejp 4ba759b): a command that hangs is
# stopped, with what it started, and the conversion fails instead of holding a
# Redmine worker for ever.
class ConversionTimeoutTest < ActiveSupport::TestCase
  include RedmineMorePreviews::TestHelper

  def hanging_worker(dir)
    worker = RedmineMorePreviews::Converter.find(:teddie).worker(:target => File.join(dir, 'preview', 'index.txt'), :preview_format => 'txt')
    marker = File.join(dir, 'still-running')
    worker.define_singleton_method(:convert) { command("sleep 30; touch #{shell_quote marker}") }
    [worker, marker]
  end

  def test_a_hanging_command_is_stopped_at_the_time_limit
    with_settings(:plugin_redmine_more_previews => { 'conversion_timeout' => '1' }) do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'a.txt'), 'x')
        worker, marker = hanging_worker(dir)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        assert_nil worker.preview(File.new(File.join(dir, 'a.txt'))) { |*_| flunk 'no result' }
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_operator elapsed, :<, 1 + RedmineMorePreviews::Lib::RmpProcess::KILL_GRACE + 2
        assert_not File.exist?(marker)
      end
    end
  end

  def test_the_time_limit_has_a_default_and_libre_gets_more
    with_settings(:plugin_redmine_more_previews => {}) do
      assert_equal RedmineMorePreviews::Constants::Defaults::CONVERSION_TIMEOUT, RedmineMorePreviews::Converter.conversion_timeout
      libre = RedmineMorePreviews::Converter.find(:libre).worker
      assert_equal 120, libre.conversion_timeout
    end
    with_settings(:plugin_redmine_more_previews => { 'conversion_timeout' => '0' }) do
      assert_equal RedmineMorePreviews::Constants::Defaults::CONVERSION_TIMEOUT, RedmineMorePreviews::Converter.conversion_timeout,
                   'the limit cannot be switched off'
    end
  end
end
