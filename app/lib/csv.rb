require 'csv'
require 'set'

group_seen_rows = Hash.new {|h,k| h[k] = Set.new}

task :csv_import do |fname, block|

  fields = {}
  task :fields do |f|
    fields.merge!(f)
  end

  comment_fields = []
  task :comment_fields do |*f|
    comment_fields.push(*f)
  end

  date_filter_block = lambda {|d| d} # default is identity
  task :date_filter do |block|
    date_filter_block = block
  end

  __reverse_entries = false
  task :reverse_entries do
    __reverse_entries = true
  end

  account_block = nil
  task :account do |block|
    account_block = block
  end

  ext_account_block = nil
  task :ext_account do |block|
    ext_account_block = block
  end

  skip_if_blocks = []
  task :skip_if do |block|
    skip_if_blocks.push(block)
  end

  date_sig = "%Y/%m/%d"
  task :date_signature do |ds|
    date_sig = ds
  end

  negate_if_blocks = []
  task :negate_if do |block|
    negate_if_blocks.push(block)
  end

  num_header_rows = 0
  task :header_rows do |num|
    num_header_rows = num
  end

  group_name = nil
  task :group do |group|
    group_name = group.to_sym
  end

  if block
    instance_exec(&block)
  end

  raise "Date field undefined" if fields[:date].nil?
  raise "Amount field undefined" if (fields[:amount].nil? && (fields[:credit_amount].nil? || fields[:debit_amount].nil?))
  raise "Payee field undefined" if fields[:payee].nil?

  entries = CSV.read(fname)
  entries = entries[num_header_rows..-1]
  if __reverse_entries
    entries.reverse!
  end
  this_group_seen_rows = Set.new
  entries.each_with_index do |row, index|
    vars = Hash[fields.map {|name, index| [name, row[index]]}]
    next if group_name && group_seen_rows[group_name].include?(vars) # duplicate prevention (only screens duplicates from OTHER import files in the same group, not from same import file)
    this_group_seen_rows.add(vars.clone) unless group_name.nil?
    begin
      vars[:date] = Date.strptime(vars[:date], date_sig)
    rescue ArgumentError => e
      raise "Invalid date: #{vars[:date].inspect} for date signature: #{date_sig.inspect}"
    end
    if vars[:amount]
      vars[:amount] = ::Funds::Amount.new(vars[:amount])
    elsif vars[:credit_amount] && vars[:debit_amount]
      debit  = ::Funds::Amount.new(vars[:debit_amount]).negate
      credit = ::Funds::Amount.new(vars[:credit_amount])
      if debit.zero?
        vars[:amount] = credit
      else
        vars[:amount] = debit
      end
    end
    account = account_block.call(vars)
    ext_account = ext_account_block.call(vars)
    vars[:amount] = vars[:amount].negate if negate_if_blocks.reduce(false) {|sum,current| sum || current.call(vars)}
    skip = skip_if_blocks.reduce(false) {|sum,current| sum || current.call(vars)}
    unless skip
      date vars[:date]
      transaction vars[:payee] do
        comment_fields.each do |field|
          comment "#{field.to_s}: #{vars[field.to_sym].to_s}"
        end
        posting account, vars[:amount]
        posting ext_account
      end
    end
  end
  unless group_name.nil? # duplicate prevention (only screens duplicates from OTHER import files in the same group, not from same import file)
    group_seen_rows[group_name].merge(this_group_seen_rows)
  end

end


