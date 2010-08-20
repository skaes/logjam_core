require 'gnuplot'
module Logjam

  class Plot

    attr_accessor :data, :filetype

    def initialize(dataset, filetype = :png)
      @data = dataset
      @filetype = filetype
      send "plot_#{dataset.plot_kind}"
    end

    def filename
      @data.path(data.send("#{filetype}_file"))
    end

    def view
      system("open #{filename}") if RUBY_PLATFORM =~ /darwin/
    end

    def xtic_labels
      (0..24).to_a.map do |n|
        ((n % 3 == 0) || (data.end_hour - data.start_hour <= 12) ? %Q{"#{n}"} : %Q{""}) +  ' ' + (n*data.intervals_per_hour).to_s
      end.join(', ')
    end

    def terminal
      case filetype
      when :png
        'png transparent size 630, 340 font "/Library/Fonts/Verdana.ttf" 8'
      when :svg
        'svg size 1000, 600 fsize 11'
      end
    end

    YLABELS = {:time => 'Response time (ms)', :call => '# of calls', :memory => 'Allocations (bytes)'}

    def ylabel
      if data.plot_kind == :call && data.resource == "requests"
        '# requests per minute'
      else
        YLABELS[data.plot_kind]
      end
    end

    def resources_excluded_from_plot
      if data.resource == "requests"
        Resource.resources_for_type(data.plot_kind) - ["requests"]
      else
        ['total_time', 'allocated_memory', 'requests']
      end
    end

    def plot
      Gnuplot.open do |gp|
        Gnuplot::Plot.new( gp ) do |plot|
          plot.terminal   terminal
          plot.output     filename
          plot.ylabel     ylabel
          plot.xlabel     'Time of day'
          plot.xrange     "[#{data.start_interval} : #{data.end_interval}]"
          plot.style      'fill solid 1.0 noborder'
          plot.style      'data histogram'
          plot.style      'histogram rowstacked'
          plot.xtics       "(#{xtic_labels}) out nomirror"
          plot.ytics      'out nomirror'
          plot.key        'below left invert'
          plot.boxwidth   '0.8'
          plot.grid       'nopolar'
          plot.grid       'xtics nomxtics ytics nomytics noztics nomztics nox2tics nomx2tics noy2tics nomy2tics nocbtics nomcbtics'
          plot.grid       'back linetype 0 linewidth 0.7'

          plot.data = []

          (Resource.resources_for_type(data.plot_kind) - resources_excluded_from_plot).reverse.each do |resource|
            next unless plot_data = data.plot_data(data.plot_kind, resources_excluded_from_plot).map{|i| (i||{})[resource]}
            plot.data << Gnuplot::DataSet.new([[resource] + plot_data]) do |ds|
              ds.title = resource.gsub(/_/,' ')
              ds.with = 'steps' if resource == 'gc_time' || resource == 'heap_size'
              ds.using = "1 lc rgb '#{Resource.colors[resource]}'"
            end
          end
        end
      end
    end

    alias plot_time plot
    alias plot_call plot

  end
end
