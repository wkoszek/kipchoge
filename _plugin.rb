def render(path)
  data = File.read(path)
  renderer = ERB.new(data)
  renderer.result(self.get_binding)
end

def suma(blog, a)
  "nothing here"
end
