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
      system("ln -nsf #{logjam_dir}/assets/images/scatter_plot.jpg #{app_dir}/public/images/scatter_plot.jpg")
      system("ln -nsf #{logjam_dir}/assets/images/zoom_in.png #{app_dir}/public/images/zoom_in.png")
      system("ln -nsf #{logjam_dir}/assets/javascripts/protovis-r3.2.js #{app_dir}/public/javascripts/protovis-r3.2.js")
    end
  end
  namespace :plots do
    desc "remove generated plots"
    task :clear do
      system("rm -f #{app_dir}/public/images/plot-*")
    end
  end
end
