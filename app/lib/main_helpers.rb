require 'dsltasks'

module MainFundsHelpers

  def active_class(path='/', class_name='active')
    a, b = [path, request.path_info].map do |path|
      path.split('/').select {|c| !c.empty?}
    end
    a == b ? class_name : nil
  end

  def funds_info(options = nil)
    options = {}.merge(options || {})
    lib_dir = File.dirname(File.expand_path(__FILE__))
    libs = []
    libs.push File.join(lib_dir, 'funds.rb')
    input_file = AppConfig['money_dsl_top']
    return DSLTasks::start(main: input_file, lib_dirs: [], libs: libs, instance_variables: {:@options => options})
  end

  def date_pretty(date)
    date.strftime("%b %e, %Y")
  end

end
