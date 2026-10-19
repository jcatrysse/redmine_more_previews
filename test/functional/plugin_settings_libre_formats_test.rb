# frozen_string_literal: true

require File.expand_path('../../test_helper', __FILE__)

# upstream 638057d, 4540b78 (curecodejp 6.1.3)
class PluginSettingsLibreFormatsTest < Redmine::ControllerTest
  tests SettingsController
  fixtures :users, :email_addresses

  def setup
    @request.session[:user_id] = 1 # administrator
    @previous = Setting.plugin_redmine_more_previews
    @settings = {
      'converter' => {
        'libre' => {
          'mime_types' => {
            'docx' => {'active' => '1', 'format' => 'html'},
            'csv' => {'active' => '1', 'format' => 'html'}
          }
        }
      }
    }
    Setting.plugin_redmine_more_previews = @settings
    Setting.clear_cache
  end

  def teardown
    Setting.plugin_redmine_more_previews = @previous
    Setting.clear_cache
  end

  def test_disallowed_format_does_not_save_settings
    updated = @settings.deep_dup
    updated['converter']['libre']['mime_types']['docx']['format'] = 'xml'
    post :plugin, params: {id: 'redmine_more_previews', settings: updated}
    assert_redirected_to '/settings/plugin/redmine_more_previews'
    assert_equal I18n.t(:error_more_previews_invalid_libre_format, locale: :en), flash[:error]
    assert_equal @settings, Setting.plugin_redmine_more_previews
  end

  def test_shell_metacharacters_in_a_format_are_not_saved
    updated = @settings.deep_dup
    updated['converter']['libre']['mime_types']['docx']['format'] = 'pdf;touch /tmp/unwanted'
    post :plugin, params: {id: 'redmine_more_previews', settings: updated}
    assert flash[:error].present?
    assert_equal @settings, Setting.plugin_redmine_more_previews
  end

  def test_error_is_shown_in_the_user_language
    User.find(1).update!(language: 'ja')
    updated = @settings.deep_dup
    updated['converter']['libre']['mime_types']['docx']['format'] = 'xml'
    post :plugin, params: {id: 'redmine_more_previews', settings: updated}
    assert_equal I18n.t(:error_more_previews_invalid_libre_format, locale: :ja), flash[:error]
    assert_not_equal I18n.t(:error_more_previews_invalid_libre_format, locale: :en), flash[:error]
  end

  def test_format_must_be_supported_by_its_extension
    updated = @settings.deep_dup
    updated['converter']['libre']['mime_types']['csv']['format'] = 'txt'
    post :plugin, params: {id: 'redmine_more_previews', settings: updated}
    assert_response :redirect
    assert flash[:error].present?
    assert_equal @settings, Setting.plugin_redmine_more_previews
  end

  def test_unknown_extension_is_not_saved
    updated = @settings.deep_dup
    updated['converter']['libre']['mime_types']['exe'] = {'active' => '1', 'format' => 'pdf'}
    post :plugin, params: {id: 'redmine_more_previews', settings: updated}
    assert flash[:error].present?
    assert_equal @settings, Setting.plugin_redmine_more_previews
  end

  def test_valid_formats_are_saved
    updated = @settings.deep_dup
    updated['converter']['libre']['mime_types']['docx']['format'] = 'txt'
    updated['converter']['libre']['mime_types']['csv']['format'] = 'pdf'
    post :plugin, params: {id: 'redmine_more_previews', settings: updated}
    assert_response :redirect
    assert flash[:error].blank?
    assert_equal updated, Setting.plugin_redmine_more_previews
  end

  # the settings page as it is posted, every converter and extension included
  def test_the_settings_page_as_shown_can_be_saved
    get :plugin, params: {id: 'redmine_more_previews'}
    assert_response :success
    formats = css_select('select[name^="settings[converter][libre][mime_types]"]')
    assert_operator formats.size, :>, 50
    settings = formats.each_with_object({}) do |select, hash|
      extension = select['name'][/\[mime_types\]\[([^\]]+)\]/, 1]
      hash[extension] = {'format' => select.at_css('option')['value']}
    end
    post :plugin, params: {id: 'redmine_more_previews', settings: {'converter' => {'libre' => {'mime_types' => settings}}}}
    assert flash[:error].blank?, flash[:error]
    assert_equal settings, Setting.plugin_redmine_more_previews['converter']['libre']['mime_types']
  end
end
