"Render an HTML file in order to send it to the frontend"
function render_html(html_file::String; status=200, headers=["Content-type" => "text/html"]) :: HTTP.Response
   io = open(html_file,"r") do file
      read(file, String)
   end
   return html(io)
end

function render_js(js_file::String; status=200, headers=["Content-type" => "text/javascript"]) :: HTTP.Response
   io = open(js_file,"r") do file
      read(file, String)
   end
   return js(io)
end