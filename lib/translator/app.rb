# frozen_string_literal: true
require 'psych'
require 'yaml'
require 'active_support/all'

require 'translator/web'
require 'translator/store'
require 'translator/core_ext'

module Translator
  # App provides Translator's top-level functionality:
  #   * Starting Translator
  #   * Loading Translation files
  #   * Saving Translation files
  class App
    attr_accessor :store

    def initialize(path, port = 5050)
      @path = File.expand_path(path)
      @port = port || 5050
      @store = Store.new
      Translator.app = self
    end

    # Starts Translator server
    def start
      raise "File #{@path} not found." unless File.exist?(@path)
      $stdout.puts " * Loading translations from #{@path}"
      load_translations

      $stdout.puts ' * Creating missing translations'
      store.create_missing_keys

      $stdout.puts " * Starting Translator at port #{@port}"
      Rack::Server.start app: Web, Port: @port
    end

    # Loads translations from a given path
    def load_translations
      files = if File.directory?(@path)
                Dir[@path + '/**/*.yml']
              elsif File.file?(@path)
                detect_list_or_file @path
              else
                $stderr.puts 'No valid translation file given'
                []
              end
      update_store files
    end

    # Write the given translations to the appropriate YAML file
    # example translations:
    # {"en.day_names"=>"Mon\r\nTue", "en.session.new.password"=>"Password"}
    def save_translations(translations)
      store.update(translations)
      changes = files(translations: translations)
      changes.each do |file, yaml|
        File.open(file, 'w', encoding: 'utf-8') do |f|
          f.puts normalize(yaml)
        end
      end
    end

    def reload
      @store=Store.new
      $stdout.puts " * Reloading translations"
      load_translations

      $stdout.puts ' * Creating missing translations'
      store.create_missing_keys      
    end

    private

    # Enables Translator to deal with inputs that reference a file list or a
    # single translation file
    def detect_list_or_file(path)
      file = YAML.load_file(path)
      file.is_a?(Hash) ? [path] : File.read(path).split
    end

    def update_store(files)
      files.each do |file|
        if File.exist?(file)
          yaml = YAML.load_file(file)
          store.from_yaml(yaml, file)
        end
      end
    end

    def files(translations: {})
      store.to_yaml.select do |_, i18n_hash|
        translations.keys.any? do |i18n_key|
          key_in_i18n_hash? i18n_key, i18n_hash
        end
      end
    end

    def key_in_i18n_hash?(i18n_key, i18n_hash)
      !i18n_key.split('.').inject(i18n_hash) do |hash, k|
        begin
          hash[k]
        rescue
          {}
        end
      end.nil?
    end

    def normalize(yaml)
      i18n_yaml = yaml.with_indifferent_access.to_hash.to_yaml
      i18n_yaml_lines = i18n_yaml.split(/\n/).reject { |e| e == '' }[1..-1]
      normalize_empty_lines(i18n_yaml_lines) * "\n"
    end

    def normalize_empty_lines(i18n_yaml_lines)
      yaml_ary = []
      i18n_yaml_lines.each_with_index do |line, idx|
        yaml_ary << line
        yaml_ary << '' if add_empty_line?(i18n_yaml_lines, line, idx)
      end
      yaml_ary
    end

    def add_empty_line?(process, line, idx)
      return if process[idx + 1].nil?
      this_line_spcs = line[/\A\s*/].length
      next_line_spcs = process[idx + 1][/\A\s*/].length
      this_line_spcs - next_line_spcs > 2
    end
  end
end
