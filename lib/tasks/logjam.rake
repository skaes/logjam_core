namespace :logjam do
  # avoid loading the rails env if it's not necessary
  def logjam_dir
    File.expand_path(File.dirname(__FILE__) + '/../../')
  end
  def app_dir
    File.expand_path(logjam_dir + '/../../../')
  end
  namespace :assets do
    desc "create symbolic links for logjam assets in the public directory"
    task :link do
      system("ln -nsf #{logjam_dir}/assets/stylesheets/logjam.css #{app_dir}/public/stylesheets/logjam.css")
      system("ln -nsf #{logjam_dir}/assets/stylesheets/jdpicker.css #{app_dir}/public/stylesheets/jdpicker.css")
      system("ln -nsf #{logjam_dir}/assets/images/scatter_plot.jpg #{app_dir}/public/images/scatter_plot.jpg")
      system("ln -nsf #{logjam_dir}/assets/images/zoom.png #{app_dir}/public/images/zoom.png")
      system("ln -nsf #{logjam_dir}/assets/images/zoom_in.png #{app_dir}/public/images/zoom_in.png")
      system("ln -nsf #{logjam_dir}/assets/images/zoom_out.png #{app_dir}/public/images/zoom_out.png")
      system("ln -nsf #{logjam_dir}/assets/images/stream.gif #{app_dir}/public/images/stream.gif")
      system("ln -nsf #{logjam_dir}/assets/images/bg_hover.png #{app_dir}/public/images/bg_hover.png")
      system("ln -nsf #{logjam_dir}/assets/images/bg_selectable.png #{app_dir}/public/images/bg_selectable.png")
      system("ln -nsf #{logjam_dir}/assets/images/bg_selected.png #{app_dir}/public/images/bg_selected.png")
      system("ln -nsf #{logjam_dir}/assets/javascripts/protovis-r3.2.js #{app_dir}/public/javascripts/protovis-r3.2.js")
      system("ln -nsf #{logjam_dir}/assets/javascripts/jquery-1.4.2.min.js #{app_dir}/public/javascripts/jquery-1.4.2.min.js")
      system("ln -nsf #{logjam_dir}/assets/javascripts/jquery.jdpicker.js #{app_dir}/public/javascripts/jquery.jdpicker.js")
    end
  end
  namespace :plots do
    desc "remove generated plots"
    task :clear do
      system("rm -f #{app_dir}/public/images/plot-*")
    end
  end
end
