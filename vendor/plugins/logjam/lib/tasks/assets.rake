namespace :logjam do
  namespace :assets do
    desc "create symbolic links for logjam assets in the public directory"
    task :link do
      logjam = File.expand_path(File.dirname(__FILE__) + '/../../')
      root = File.expand_path(logjam + '/../../../')
      system("ln -nsf #{logjam}/assets/stylesheets/scaffold.css #{root}/public/stylesheets/scaffold.css")
    end
  end
end
