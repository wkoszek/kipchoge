#!/usr/bin/env ruby
# vim:tw=1000:

require 'erb'
require 'yaml'
require 'json'
require 'pp'
require 'fileutils'
require 'ostruct'
require 'byebug'

require_relative '_plugin.rb'

class Article
  attr_accessor :data, :filename, :blog

  def initialize(filename, blog)
    @filename = filename
    @data_raw = File.read(@filename)
    @data_tmp = parse_data(@data_raw)
    @data_tmp['filename'] = filename
    @data_tmp['render_time'] = Time.new
    @data = OpenStruct.new(@data_tmp)
    @blog = blog
  end

  def parse_data(data_raw)
    ret = {}
    if data_raw =~ /^---/ then
      chunks_all = data_raw.split(/---\n/).select { |c| c != "" }
      frontmatter, article_body = chunks_all[0], chunks_all[1]
      ret = YAML.load(frontmatter)
      ret['article_body'] = article_body
    else
      ret['article_body'] = data_raw
    end
    ret
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
  def render(path, obj = self)
    data = File.read(path)
    renderer = ERB.new(data)
    renderer.result(obj.get_binding)
  end
  def add_all
    Dir["#{@cfg.dirs.source}/**/*.md"].each do |dir_entry|
      article_one = Article.new(dir_entry, self)
      add(article_one)
    end
  end
  def render_all
    @articles.each do |a|
      print a.filename
      layout_name = a.data._layout || "page"
      layout_file = @cfg.layout[layout_name]
      STDERR.puts "using layout: #{layout_file}"
      #layout_file = "_layout_post.erb"
      puts render(layout_file, a)
      #sleep 2
    end
  end
end

class Config
  attr_accessor :cfg
  def initialize(config_file = '_config.yml')
    yaml = YAML.load(File.read(config_file))
    json = yaml.to_json
    @cfg = JSON.parse(json, object_class: OpenStruct)
  end
end

def main
  cfg = Config.new().cfg

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
