# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

class PluginSettingsLimitsTest < Redmine::ControllerTest
  tests SettingsController

  fixtures :users, :email_addresses

  def setup
    @request.session[:user_id] = 1 # admin
    @old_settings = Setting.plugin_redmine_more_previews
  end

  def teardown
    Setting.plugin_redmine_more_previews = @old_settings
    Setting.clear_cache
  end

  def test_limits_are_shown_with_their_defaults
    Setting.plugin_redmine_more_previews = @old_settings.to_h.except('conversion_timeout', 'lock_timeout', 'max_conversions')
    get :plugin, params: {id: 'redmine_more_previews'}
    assert_response :success
    assert_select 'input[name=?][value=?]', 'settings[conversion_timeout]', '60'
    assert_select 'input[name=?][value=?]', 'settings[lock_timeout]', '5'
    assert_select 'input[name=?][value=?]', 'settings[max_conversions]', '2'
  end

  def test_limits_are_saved
    post :plugin, params: {id: 'redmine_more_previews',
                           settings: @old_settings.to_h.merge('conversion_timeout' => '30', 'lock_timeout' => '3', 'max_conversions' => '4')}
    Setting.clear_cache
    assert_equal 30, RedmineMorePreviews::Converter.conversion_timeout
    assert_equal 3, RedmineMorePreviews::Converter.lock_timeout
    assert_equal 4, RedmineMorePreviews::Converter.max_conversions
  end

  def test_limits_cannot_be_switched_off
    post :plugin, params: {id: 'redmine_more_previews',
                           settings: @old_settings.to_h.merge('conversion_timeout' => '0', 'lock_timeout' => '-1', 'max_conversions' => 'none')}
    Setting.clear_cache
    assert_equal 60, RedmineMorePreviews::Converter.conversion_timeout
    assert_equal 5, RedmineMorePreviews::Converter.lock_timeout
    assert_equal 2, RedmineMorePreviews::Converter.max_conversions
  end

  def test_limits_are_described
    get :plugin, params: {id: 'redmine_more_previews'}
    assert_select 'fieldset legend', :text => 'Conversion limits'
    assert_select '#help_redmine_more_previews_limits', :text => /stopped with all the programs it started/
  end
end
