require 'jasmine_rails/offline_asset_paths'

module JasmineRails
  module Runner
    class << self
      # Run the Jasmine testsuite via phantomjs CLI
      # raises an exception if any errors are encountered while running the testsuite
      def run(spec_filter = nil, reporters = 'console')
        start_time = Time.now
        puts "Starting Runner.run"
        override_rails_config do
          require 'phantomjs' if JasmineRails.use_phantom_gem?
          require 'fileutils'
          puts "Required phantomjs and fileutils, T+#{Time.now - start_time}"

          include_offline_asset_paths_helper
          html = get_spec_runner(spec_filter, reporters)
          puts "Got spec runner, T+#{Time.now - start_time}"
          FileUtils.mkdir_p JasmineRails.tmp_dir
          runner_path = JasmineRails.tmp_dir.join('runner.html')
          asset_prefix = Rails.configuration.assets.prefix.gsub(/\A\//,'')
          File.open(runner_path, 'w') {|f| f << html.gsub("/#{asset_prefix}", "./#{asset_prefix}")}

          phantomjs_runner_path = File.join(File.dirname(__FILE__), '..', 'assets', 'javascripts', 'jasmine-runner.js')
          phantomjs_cmd = JasmineRails.use_phantom_gem? ? Phantomjs.path : 'phantomjs'
          puts "Running tests, T+#{Time.now - start_time}"
          run_cmd %{"#{phantomjs_cmd}" "#{phantomjs_runner_path}" "#{runner_path.to_s}?spec=#{spec_filter}"}
          puts "Finished!, T+#{Time.now - start_time}"
        end
      end

      private
      def include_offline_asset_paths_helper
        if Rails::VERSION::MAJOR >= 4
          Sprockets::Rails::Helper.send :include, JasmineRails::OfflineAssetPaths
        else
          ActionView::AssetPaths.send :include, JasmineRails::OfflineAssetPaths
        end
      end

      # temporarily override internal rails settings for the given block
      # and reset the settings after work is complete.
      #
      # * disable Rails assets debug setting to ensure generated application
      # is built into one JS file
      # * disable asset host so that generated runner.html file uses
      # relative paths to included javascript files
      def override_rails_config
        config = Rails.application.config

        original_assets_debug = config.assets.debug
        original_assets_host = ActionController::Base.asset_host
        config.assets.debug = false
        ActionController::Base.asset_host = nil
        yield
      ensure
        config.assets.debug = original_assets_debug
        ActionController::Base.asset_host = original_assets_host
      end

      def get_spec_runner(spec_filter, reporters)
        start_time = Time.now
        puts "Start get_spec_runner (T=#{Time.now - start_time})"
        app = ActionDispatch::Integration::Session.new(Rails.application)
        puts "Got app (T=#{Time.now - start_time})"
        app.https!(JasmineRails.force_ssl)
        puts "Forced SSL (T=#{Time.now - start_time})"
        path = JasmineRails.route_path
        puts "got path (T=#{Time.now - start_time})"
        JasmineRails::OfflineAssetPaths.disabled = false
        app.get path, :reporters => reporters, :spec => spec_filter
        JasmineRails::OfflineAssetPaths.disabled = true
        puts "app.get path (T=#{Time.now - start_time})"
        unless app.response.success?
          raise "Jasmine runner at '#{path}' returned a #{app.response.status} error: #{app.response.message} \n\n" +
                "The most common cause is an asset compilation failure. Full HTML response: \n\n #{app.response.body}"
        end
        app.response.body
      end

      def run_cmd(cmd)
        puts "Running `#{cmd}`"
        unless system(cmd)
          raise "Error executing command: #{cmd}"
        end
      end
    end
  end
end
