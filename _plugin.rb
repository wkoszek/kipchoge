def render(path)
  data = File.read(path)
  renderer = ERB.new(data)
  renderer.result(self.get_binding)
end
def partial(fn)
  ffn = File.join(self.blog.cfg.dirs.source, fn)
  File.read(ffn)
end

def partial_google_analytics
  html = %q{
  <script>
    (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
    (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
    m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
    })(window,document,'script','//www.google-analytics.com/analytics.js','ga');
    ga('create', 'UA-XXXXXXX-X', 'auto');
    ga('send', 'pageview');
  </script>}

  html.gsub! "UA-XXXXXXX-X", self.blog.cfg.plugin.google_analytics.id
  html
end

def partial_statcounter
  html = %q{
  <script type="text/javascript">
  var sc_project=SC_PROJECT;
  var sc_invisible=0;
  var sc_security="SC_SECURITY";
  var sc_text=2;
  var scJsHost = (("https:" == document.location.protocol) ?  "https://secure." : "http://www.");
  document.write("<sc"+"ript type='text/javascript' src='" + scJsHost+ "statcounter.com/counter/counter.js'></"+"script>");
  </script>
  <noscript>
  <div class="statcounter">
  <a title="free web stats" href="https://statcounter.com/free-web-stats/" target="_blank">
  <img class="statcounter" src="https://c.statcounter.com/SC_PROJECT/0/SC_SECURITY/0/" alt="free web stats"></a>
  </div>
  </noscript>
  }
  html.gsub! "SC_PROJECT", self.blog.cfg.plugin.statcounter.sc_project
  html.gsub! "SC_SECURITY", self.blog.cfg.plugin.statcounter.sc_security
end
