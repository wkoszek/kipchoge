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

require_relative '_plugin.rb'

class Debug
  def self.dbg(*args)
#    return
    STDERR.puts *args
  end
end

class Article
  attr_accessor :data, :filename, :blog

  def initialize(filename, blog)
    @filename = filename
    @filename_base = File.basename(filename)
    @data_raw = File.read(@filename)
    @blog = blog

    @data_tmp = parse_data(@data_raw)
    @data_tmp['layout_file'] = @blog.cfg.layout[@data_tmp['_layout'] || "page"]
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

  def date_from_filename(filename)
    d = filename[0..'yyyy-mm-dd'.length]
    if filename =~ /^\d{4}-\d{2}-\d{2}/
      Time.parse(filename[0..'yyyy-mm-dd'.length])
    else
      Time.parse('1970-01-01')
    end
  end

  def filename_output(cfg)
    fn_tmp = @filename.split('.')[0] + ".html"
    fn_out = fn_tmp.sub(/^#{cfg.dirs.source}/, cfg.dirs.dest)
    path_parts = fn_out.split('/')
    dir_out = path_parts[0..-2].join('/')

    fn_base = path_parts[-1]
    if fn_base =~ /^\d{4}-\d{2}-\d{2}/
      3.times { fn_base.sub!('-', '/') }
    end
    dir_out + '/' + fn_base
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
  end
  def add(a)
    @articles << a
  end
  def get_binding
    binding()
  end

  def render_data(data, obj = self)
    renderer = ERB.new(data)
    renderer.result(obj.get_binding)
  end

  # XX remember to add File cache here
  def render(path, obj = self)
    data = File.read(path)
    render_data(data, obj)
  end

  def add_all
    cfg_dirs = "#{@cfg.dirs.source}/#{@cfg.dirs.pattern}"
    Debug.dbg ">>", cfg_dirs
    Dir[cfg_dirs].each do |dir_entry|
      Debug.dbg "> rendering #{dir_entry}"
      article_one = Article.new(dir_entry, self)
      add(article_one)
    end
  end

  def render_one(a)
      fn_out = a.filename_output(@cfg)
      dir_out = File.dirname(fn_out)
      Debug.dbg "using layout: #{a.data.layout_file} FOUT #{fn_out} DIROUT #{dir_out}"

      Debug.dbg "first stage"
      # .md >> erb >> md >> flat_md
      rendered_body = render_data(a.data.article_body, a)
      a.data.article_body = Kramdown::Document.new(rendered_body).to_html

      Debug.dbg "second stage"
      # flat_md >> erb_layout >> view_md
      rendered_body = render(a.data.layout_file, a)
      a.data.article_body = rendered_body
   
      Debug.dbg "third stage"
      # view_md >> wrapping erb >> final
      rendered_body = render('_layout_all.erb', a)

      body_to_write = rendered_body

      FileUtils.mkdir_p(dir_out)
      File.write(fn_out, body_to_write)
  end

  def render_all
    work_q = Queue.new
    @articles.each do |a|
      work_q.push a
    end

    workers = (0...4).map do
      Thread.new do
        begin
          while x = work_q.pop(true)
            render_one(x)
          end
        rescue ThreadError
        end
      end
    end;
    workers.map(&:join);

    STDOUT.puts "rendered #{articles.length} files"
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
  cfg = Konfig.new().cfg

  dirs_init(cfg)

  blog = Blog.new(cfg)
  blog.add_all
  blog.render_all
end

def dirs_init(cfg)
  system("mkdir -p #{cfg.dirs.dest} 2>/dev/null")
  system("cd #{cfg.dirs.source} && find . -type d -print0 | (cd ../#{cfg.dirs.dest} && xargs -0 mkdir) 2>/dev/null")
end

main
