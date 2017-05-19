#!/usr/bin/env ruby
# vim:tw=1000:

require 'erb'
require 'time'
require 'yaml'
require 'json'
require 'pp'
require 'fileutils'
require 'ostruct'
require 'byebug'
require 'kramdown'
require 'parallel'
require 'digest'
require 'webrick'

require_relative '_plugin.rb'

class Debug
  @@is_enabled = 0
  def self.enable
    @@is_enabled = 1
  end
  def self.dbg(*args)
    if @@is_enabled == 0
      return
    end
    STDERR.puts *args
  end
end

class Article
  attr_accessor :data, :filename, :blog

  def initialize(filename, index, blog)
    @filename = filename
    @filename_base = File.basename(filename)
    @data_raw = File.read(@filename)
    @blog = blog

    @data_tmp = parse_data(@data_raw)
    @data_tmp['index'] = index
    @data_tmp['link'] = filename_output.sub(/^#{@blog.cfg.dirs.dest}\//, '')
    @data_tmp['layout_file'] = get_layout_file(@data_tmp['klayout'] || "page")
    @data_tmp['filename'] = filename
    @data_tmp['filename_base'] = @filename_base
    @data_tmp['written_date'] = date_from_filename(@filename_base)
    @data_tmp['render_time'] = Time.new
    @data = OpenStruct.new(@data_tmp)
  end

  def parse_data(data_raw)
    ret = {}
    if data_raw =~ /^---/ then
      chunks_all = data_raw.split(/---\n/).select { |c| c != "" }
      frontmatter = chunks_all[0]
      article_body = chunks_all[1] || ""
      ret = YAML.load(frontmatter)
      ret['article_body'] = article_body
    else
      ret['article_body'] = data_raw
    end
    ret
  end

  def get_layout_file(layout_name)
    File.join(@blog.cfg.theme, 'layout', "layout_#{layout_name}.erb")
  end

  def date_from_filename(filename)
    d = filename[0..'yyyy-mm-dd'.length]
    if filename =~ /^\d{4}-\d{2}-\d{2}/
      Time.parse(filename[0..'yyyy-mm-dd'.length])
    else
      # Add file creation/modification date? See if Git preserves that.
      Time.parse('1970-01-01')
    end
  end

  def filename_output(cfg = @blog.cfg)
    fn_tmp = @filename.split('.')[0] + ".html"
    fn_out = fn_tmp.sub(/^#{cfg.dirs.source}/, cfg.dirs.dest)
    path_parts = fn_out.split('/')
    dir_out = path_parts[0..-2].join('/')

    fn_base = path_parts[-1]
    if fn_base =~ /^\d{4}-\d{2}-\d{2}/
      3.times { fn_base.sub!('-', '/') }
    end
    File.join(dir_out, fn_base)
  end

  def get_binding
    binding()
  end
end

class Blog
  attr_accessor :articles, :cfg

  def initialize(cfg)
    @articles = []
    @cfg = cfg
    @cache = {}
  end
  def add(a)
    @articles << a
  end
  def get_binding
    binding()
  end

  def file_cache_get(file)
    if not @cache.keys.include? file
      @cache[file] = File.read(file)
    end
    return @cache[file]
  end

  def render_data(data, obj = self)
    renderer = ERB.new(data)
    renderer.result(obj.get_binding)
  end

  def render(path, obj = self)
    Debug.dbg ">> rendering the path #{path}"
    data = file_cache_get(path)
    render_data(data, obj)
  end

  def add_all
    cfg_dirs = File.join(@cfg.dirs.source, @cfg.dirs.pattern)
    Debug.dbg ">>", cfg_dirs
    Dir[cfg_dirs].each_with_index do |dir_entry, dir_entry_idx|
      Debug.dbg "> adding #{dir_entry}"
      article_one = Article.new(dir_entry, dir_entry_idx, self)
      add(article_one)
    end
    @articles.sort_by!{ |o| o.data.written_date }
  end

  def render_one(a)
    fn_out = a.filename_output(@cfg)
    dir_out = File.dirname(fn_out)
    Debug.dbg "using layout: #{a.data.layout_file} FOUT #{fn_out} DIROUT #{dir_out}"

    Debug.dbg "first stage"
    # .md >> erb >> md >> flat_md
    rendered_body = render_data(a.data.article_body, a)
    a.data.article_body = Kramdown::Document.new(rendered_body).to_html

    Debug.dbg "second stage: #{a.data.layout_file}"
    # flat_md >> erb_layout >> view_md
    rendered_body = render(a.data.layout_file, a)
    a.data.article_body = rendered_body

    Debug.dbg "third stage"
    # view_md >> wrapping erb >> final
    rendered_body = render(File.join(@cfg.theme, 'layout', 'layout_all.erb'), a)

    body_to_write = rendered_body

    FileUtils.mkdir_p(dir_out)
    File.write(fn_out, body_to_write)
  end

  def render_many(art_to_render = @articles)
    if art_to_render.length == 0
      return
    end
    results = Parallel.map(art_to_render, in_processes: 4) { |a|
      render_one(a)
    }
    STDOUT.puts "rendered #{art_to_render.length} files"
  end
end

class Server
  def initialize(args = {})
    @blog = args[:blog]
    @port = ENV['KIPCHOGE_PORT'] || args[:port] || 9123
    @bind = ENV['KIPCHOGE_BIND'] || args[:bind] || '127.0.0.1'
  end

  def monitor
    serv_proc = fork {
      server = WEBrick::HTTPServer.new({
        :DocumentRoot => @blog.cfg.dirs.dest,
        :BindAddress => @bind,
        :Port => @port,
      })
      ['INT', 'TERM'].each {|s| Signal.trap(s) {
          STDERR.puts "Shutting down server..."
          server.shutdown
      }}
      server.start
    }

    STDERR.puts "Server started, PID #{serv_proc}"
    STDERR.puts "-"*80,"Enter: http://#{@bind}:#{@port}/",'-'*80
    Process.detach(serv_proc)
    ['INT', 'TERM'].each {|s| Signal.trap(s) {
      Process.kill(s, serv_proc)
      exit
    }}

    while true
      build
      sleep 0.5
    end
  end

  def build
    dir_map = dir_map_make_or_load
    do_all = false
    fn_to_regen = []

    Debug.dbg ">> scanning"

    dir_map['file_state_all'].each do |dm|
      dm_fn, dm_mtime = dm['fn'], dm['mtime']
      next if File.exist?(dm_fn) && File.mtime(dm_fn) == dm_mtime

      if dm_fn =~ /#{@blog.cfg.monitor.render.all}/
        STDERR.puts "#{dm_fn} changed. Will render everything"
        do_all = true
        break
      elsif dm_fn =~ /#{@blog.cfg.monitor.render.one}/
        STDERR.puts "#{dm_fn} changed. Will add to resources to be rendered"
        fn_to_regen << dm_fn
      end
    end

    art_to_regen = do_all ? @blog.articles : @blog.articles.select {|a|
      fn_to_regen.include?(a.filename)
    }
    art_to_regen += @blog.articles.select {|a|
      !File.exist?(a.filename_output(@blog.cfg))
    }

    @blog.render_many(art_to_regen)
    File.write(dir_map_fn, YAML.dump(dir_map_make))
  end

  def dir_map_make_or_load
    dir_map = nil
    if not File.exist?(dir_map_fn)
      Debug.dbg "Didn't find map. Renenerating #{dir_map_fn}"
      dir_map = dir_map_make(@blog.cfg.dirs.source)
      File.write(dir_map_fn, YAML.dump(dir_map))
    else
      Debug.dbg "Found map. Loading..."
      dir_map = YAML.load(File.read(dir_map_fn))
    end
    dir_map
  end

  def dir_map_make(dir_src = @blog.cfg.dirs.source)
    file_state_all = []
    dir_theme = File.join(@blog.cfg.theme, 'layout')
    [ Dir[dir_src + "/**/*"], Dir[dir_theme + "/**/*"] ].each do |dir|
      dir.each do |file_name|
        file_state_all << { "fn" =>  file_name, "mtime" => File.mtime(file_name) }
      end
    end
    data = {}
    data['file_state_all'] = file_state_all.sort_by{|fs| fs['fn'] }
    Debug.dbg "# mapped #{file_state_all.length} files"
    data
  end

  def dir_map_fn
    File.join(@blog.cfg.dirs.dest, '.kipchoge_index.yml')
  end
end

class Konfig
  attr_accessor :cfg
  def initialize(config_file = '_config.yml')
    yaml = YAML.load(File.read(config_file))
    json = yaml.to_json
    @cfg = JSON.parse(json, object_class: OpenStruct)
  end
end

def main
  do_monitor = false
  ARGV.each do |arg|
    if arg =~ /-d/
      Debug.enable()
    end
    if arg =~ /-m/
      do_monitor = true
    end
  end
  cfg = Konfig.new().cfg

  dirs_init(cfg)

  blog = Blog.new(cfg)
  blog.add_all

  s = Server.new({ :blog => blog })
  if do_monitor
    s.monitor
  else
    s.build
  end
end

def dirs_init(cfg)
  FileUtils.mkdir_p(cfg.dirs.dest)
  system("rsync -ra #{cfg.dirs.source}/ #{cfg.dirs.dest}")

  asset_from = File.join(cfg.theme, 'assets')
  asset_to = File.join(cfg.dirs.dest, 'assets')
  system("rsync -ra #{asset_from}/ #{asset_to}/")
  # TODO: will have to remove unwanted files.
end

main
