require 'thor'
require 'valkyrie_benchmark'
module ValkyrieBenchmark
  class CLI < Thor

    desc "start", "Runs benchmarks"
    method_option :adapters, aliases: ['-a'], type: :array, desc: "List of adapters to use"
    method_option :noadapters, aliases: ['-A'], type: :array, desc: "List of adapters NOT to use"
    method_option :tests, aliases: ['-t'], type: :array, desc: "List of tests to run"
    method_option :force, aliases: '-f', type: :boolean, default: false, desc: "Force use of adapter or test even if it is not enabled"
    method_option :time, type: :numeric, default: 5.0, desc: "Number of seconds to run each benchmark"
    method_option :warmup, type: :numeric, default: 2.0, desc: "Number of seconds to warmup each benchmark"
    method_option :clean, aliases: ['-c'], type: :boolean, default: true, desc: "Clean and prepare database between every test. Increases runtime but gives more consistent results."
    method_option :"test-options", type: :hash, desc: "Options to pass the test suites."
    def start
      adapters = options[:adapters].try(:map) do |a| 
        resolve_adapter(a) || puts("Couldn't resolve adapter #{a}")
      end || ValkyrieBenchmark.enabled_metadata_adapters
      options[:noadapters].try(:each) do |exclude|
        adapters.delete_if do |a| resolve_adapter(exclude) == a end
      end
      tests = options[:tests].try(:map) do |t| 
        resolve_test_suite(t) || puts("Couldn't resolve test suite #{t}")
      end || ValkyrieBenchmark.enabled_test_suites
      return if adapters.any?(&:nil?) || tests.any?(&:nil?)

      if !options[:force] 
        found = false
        adapters.select do |a| !a.enabled? end .each do |a|
          found = true
          puts("Adapter #{a.adapter_key} is not enabled. Run with -f to force using this adapter.")
        end
        tests.select do |t| !t.enabled? end .each do |t|
          found = true
          puts("Test suite #{t.suite_key} is not enabled. Run with -f to force using this test suite.")
        end
        return if found
      end

      test_suite_options = {clean_tests: options[:clean]}.merge((options[:"test-options"] || {}).symbolize_keys)

      runner = ValkyrieBenchmark::Runner.new(
        metadata_adapters: adapters, 
        test_suites: tests,
        benchmark_time: options[:time].to_f,
        warmup_time: options[:warmup_time].to_f
      )
      runner.run_all(test_suite_options)
      
    end

    desc "migrate ADAPTER", "Runs database migrations for given adapter"
    method_option :force, aliases: '-f', desc: "Run migration even if adapter is not enabled"
    def migrate(adapter)
      adapter = resolve_adapter(adapter)

      unless adapter
        puts "Couldn't resolve adapter #{adapter}"
        return
      end

      unless options[:force] || adapter.enabled? || @force
        puts "Adapter is not enabled. Run with -f to force migration."
        return
      end

      puts "Running database migrations for #{adapter.adapter_key}"
      adapter.migrate
    end

    desc "migrate_all", "Runs database migrations for all adapters"
    method_option :all, aliases: '-a', desc: "Include all adapters, even those which are not enabled"
    def migrate_all
      @force = true if options[:all]
      ValkyrieBenchmark.metadata_adapters.each do |adapter|
        next unless adapter.enabled? || options[:all]
        migrate(adapter)
      end
    end

    desc "metadata_adapters", "Lists all metadata adapters"
    method_option :all, aliases: '-a', desc: "Include all test suites, even those which are not enabled"
    def metadata_adapters
      ValkyrieBenchmark.all_metadata_adapters.each do |adapter|
        next unless adapter.enabled? || options[:all]
        puts adapter.adapter_key
      end      
    end

    desc "test_suites", "Lists all test suites"
    def test_suites
      ValkyrieBenchmark.all_test_suites.each do |suite|
        next unless suite.enabled? || options[:all]
        puts suite.suite_key
      end
    end

    no_commands do
      def resolve_adapter(adapter_key)
        return adapter_key unless adapter_key.is_a?(String)
        ValkyrieBenchmark.all_metadata_adapters.find do |a| a.adapter_key == adapter_key end
      end

      def resolve_test_suite(suite_key)
        return suite_key unless suite_key.is_a?(String)
        ValkyrieBenchmark.all_test_suites.find do |t| t.suite_key == suite_key end
      end

    end
  end
end
