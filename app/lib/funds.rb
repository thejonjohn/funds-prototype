require 'date'
require 'yaml'
require 'csv'
require 'set'

module ::Funds

  # given a string, interpret as a US dollars amount and return an integer number of pennies
  def parse_amount(amount)
    amount = amount.gsub(",","")
    result = 0
    raise "parse_amount(amount): amount must be a string" unless amount.kind_of?(String)
    if (match = amount.match(/(-)?(\$)?(-)?(\d+)?(\.(\d(\d)?))?/))
      raise "Invalid amount string: #{amount}" if match[1] && match[3]
      negative_term = (match[1] || match[3]) ? -1 : 1
      dollars = match[4] ? match[4].to_i : 0
      cents = nil
      if match[6]
        if match[6].length == 1
          cents = (match[6] + "0").to_i
        else
          cents = match[6].to_i
        end
      else
        cents = 0
      end
      result = negative_term * (dollars * 100 + cents)
    else
      raise "Unrecognized amount string: #{amount}"
    end
    result
  end
  module_function :parse_amount

  def pennies_to_s(amount, delimeter='')
    result = nil
    negative = amount < 0
    penny_s = "%02d" % amount.abs
    if penny_s.length == 2
      result = "0." + penny_s
    else
      result = penny_s[0..-3].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1'+delimeter).reverse + "." + penny_s[-2..-1]
    end
    result = "$" + result
    if negative
      result = "-" + result
    end
    return result
  end
  module_function :pennies_to_s

  class Amount
    include Comparable

    attr_reader :pennies

    def self.[](amount)
      self.new(amount)
    end

    def initialize(amount)
      if amount.kind_of?(self.class)
        @pennies = amount.pennies
      elsif amount.kind_of?(Integer) # assume in pennies
        @pennies = amount
      elsif # force to string and parse
        @pennies = ::Funds::parse_amount(amount.to_s)
      end
    end

    def <=>(other)
      @pennies <=> other.pennies
    end

    def +(other)
      other_pennies = other.kind_of?(self.class) ? other.pennies : self.class.new(other).pennies
      self.class.new(@pennies + other_pennies)
    end

    def -(other)
      other_pennies = other.kind_of?(self.class) ? other.pennies : self.class.new(other).pennies
      self.class.new(@pennies - other_pennies)
    end

    def -@
      self.class.new(0 - @pennies)
    end

    def negative?
      return @pennies < 0
    end

    def positive?
      return @pennies > 0
    end

    def zero?
      return @pennies == 0
    end

    def negate
      self.class.new(-@pennies)
    end

    def to_s(delimeter='')
      return ::Funds::pennies_to_s(@pennies, delimeter)
    end

  end

  class AccountNode

    attr_reader :children
    attr_accessor :running_total
    attr_accessor :inclusive_running_total
    attr_accessor :inclusive_running_promises
    attr_accessor :running_promises
    attr_reader :register
    attr_reader :name
    attr_reader :parent

    def initialize(name, parent=nil, root=nil, register=nil)
      @name = name
      @parent = parent
      @root = root || self
      @register = register || @root.register
      @children = Hash.new {|h,k| h[k] = self.class.new(k, self, @root) } # @children[path_component] = child

      @running_total           = Amount[0]
      @inclusive_running_total = Amount[0]

      @running_promises = Hash.new {|h,k| h[k] = Amount[0]} # @running_promises[promised_to_account] = amount_promised
      @inclusive_running_promises = Hash.new {|h,k| h[k] = Amount[0]} # @inclusive_running_promises[promised_to_account] = amount_promised
      @full_name = nil
      @parents = nil
    end

    def leaf?
      return @children.length == 0
    end

    def dfs_nodes
      child_nodes = @children.values.sort {|a,b| a.name <=> b.name}
      return child_nodes.map {|cn| [cn, cn.dfs_nodes]}.flatten
    end

    def parents
      if @parents.nil?
        @parents = []
        current_node = self.parent
        while (current_node && current_node != @root)
          @parents.push(current_node)
          current_node = current_node.parent
        end
      end
      return @parents
    end

    def self.name_to_hierarchy(name)
      return name.split(':')
    end

    # path can be a colon-separated string or array of strings(hierarchical path)
    def find_or_create_child(path)
      path = self.class.name_to_hierarchy(path) if path.kind_of?(String)
      raise "bad account path" unless path.kind_of?(Array)
      result = self
      while path.length > 0
        result = result.children[path.shift]
      end
      return result
    end
    alias_method '[]', :find_or_create_child

    def full_name
      if @full_name.nil?
        @full_name = [*(parents.reverse.map {|p| p.name}), @name].join(':') 
      end
      return @full_name
    end

    def inclusive_total_promised
      return @inclusive_running_promises.values.inject(:+) || ::Funds::Amount[0]
    end

    def total_promised
      return @running_promises.values.inject(:+) || ::Funds::Amount[0]
    end

    def amount_available
      @running_total - total_promised()
    end

    def register_snapshot_info(other_accounts)
      leaf_accounts = ([self] | other_accounts)
      leaf_current_balances = Hash[leaf_accounts.map {|a| [a, a.running_total]}]
      leaf_current_promised_balances = Hash[leaf_accounts.map {|a| [a, a.total_promised]}]
      inclusive_accounts = [self] | other_accounts | self.parents | other_accounts.map {|a| a.parents}.inject(:|)
      inclusive_current_balances = Hash[inclusive_accounts.map {|a| [a, a.inclusive_running_total]}]
      inclusive_current_promised_balances = Hash[inclusive_accounts.map {|a| [a, a.inclusive_total_promised]}]

      result = {
        leaf_current_balances: leaf_current_balances,
        leaf_current_promised_balances: leaf_current_promised_balances,
        inclusive_current_balances: inclusive_current_balances,
        inclusive_current_promised_balances: inclusive_current_promised_balances,
      }
      return result
    end

    def transfer_to(date, account, amount, payee, comments=nil)
      unless account.kind_of?(self.class)
        account = @root.find_or_create_child(account.to_s)
      end
      unless amount.kind_of?(::Funds::Amount)
        amount = ::Funds::Amount[amount]
      end
      comments ||= []

      @running_total -= amount
      @inclusive_running_total -= amount
      parents.each {|p| p.inclusive_running_total -= amount}


      account.running_total += amount
      account.inclusive_running_total += amount
      account.parents.each {|p| p.inclusive_running_total += amount}

      # attempt to resolve promises
      # rules:
      #   each descendant of this account that has a promise to the account being transferred to
      #   should get a transfer from this account to itself and get its promise resolved (up
      #   until the money involved in the transfer runs out)
      #   but first, any negative promises (meaning credit card refund) should also be handled
      
      descendants = []
      to_traverse = @children.values.clone
      until to_traverse.empty?
        current_descendant = to_traverse.shift
        descendants.push current_descendant
        to_traverse.push(*(current_descendant.children.values))
      end

      promise_participants = []

      # look for negative promises
      negative_promise_amount_to_account_for = ::Funds::Amount[0]
      descendants.each do |current_descendant|
        promise_amount = current_descendant.running_promises[account]
        if promise_amount.negative?
          if negative_promise_amount_to_account_for < amount
            promise_participants.push(current_descendant)
            amount_to_resolve = [-(amount + negative_promise_amount_to_account_for), promise_amount].max
            negative_promise_amount_to_account_for += amount_to_resolve
            current_descendant.transfer_to(date, self, amount_to_resolve, "PROMISED REFUND TRANSFER - #{current_descendant.full_name}")
            current_descendant.running_promises[account] -= amount_to_resolve
            current_descendant.inclusive_running_promises[account] -= amount_to_resolve
          end
        end
      end

      amount_left = ::Funds::Amount[amount] - negative_promise_amount_to_account_for
      descendants.each do |current_descendant|
        break if amount_left <= ::Funds::Amount[0]
        if (amount_promised = current_descendant.running_promises[account]).positive?
          promise_participants.push(current_descendant)
          amount_to_resolve = [amount_left, amount_promised].min
          current_descendant.transfer_to(date, self, amount_to_resolve, "PROMISED TRANSFER - #{current_descendant.full_name}")
          current_descendant.running_promises[account] -= amount_to_resolve
          current_descendant.inclusive_running_promises[account] -= amount_to_resolve
          current_descendant.parents.each {|p| p.inclusive_running_promises[account] -= amount_to_resolve}
        end
      end

      # to_traverse = @children.values.clone
      # until to_traverse.empty? || amount_left <= ::Funds::Amount[0]
      #   current_descendant = to_traverse.shift
      #   to_traverse.push(*(current_descendant.children.values))
      # end

      @register.push({
         type: :transfer,
         date: date,
         from_account: self,
         to_account: account,
         amount: amount,
         payee: payee,
         comments: comments
      }.merge(register_snapshot_info([account] | promise_participants)))
    end

    def process_transaction(transaction)
      # create a list of from, to, amount that satisfies the transaction
      # example:
      #   A -10
      #   B -20
      #   C 30
      #
      #   A => C 10
      #   B => C 20
      #
      # example:
      #   A 10
      #   B 40
      #   C -50
      #   
      #   C => A 10
      #   C => B 40
      #
      # ambiguous example (not allowed):
      #   A -10
      #   B -15
      #   C 12
      #   D 13
      #
      #   The sums add up but it's impossible to tell if A went to C or D

      date = transaction[:date]
      postings = transaction[:postings]
      comments = transaction[:comments]

      from_postings = []
      to_postings = []

      postings.each do |posting|
        if posting[:amount].negative?
          from_postings.push posting
        elsif posting[:amount].positive?
          to_postings.push posting
        else
          # ignore postings with zero amount
        end
      end

      if from_postings.length == 1
        from_account = self[from_postings[0][:account]]
        to_postings.each do |to_posting|
          to_account = self[to_posting[:account]]
          from_account.transfer_to(date, to_account, to_posting[:amount], transaction[:payee], comments)
        end
      elsif to_postings.length == 1
        to_account = self[to_postings[0][:account]]
        from_postings.each do |from_posting|
          from_account = self[from_posting[:account]]
          from_account.transfer_to(date, to_account, from_posting[:amount].negate, transaction[:payee], comments)
        end
      else
        raise "Invalid postings:\n#{transaction.to_yaml}"
      end
    end

    def process_promise(promise)
      date = promise[:date]
      from_account =  self[promise[:from]]
      to_account = self[promise[:to]]
      amount = promise[:amount]
      from_account.promise_to(date, to_account, amount)
    end

    def promise_to(date, account, amount)
      unless account.kind_of?(self.class)
        account = @root.find_or_create_child(account.to_s)
      end
      unless amount.kind_of?(::Funds::Amount)
        amount = ::Funds::Amount[amount]
      end

      @running_promises[account] += amount
      @inclusive_running_promises[account] += amount
      self.parents.each {|p| p.inclusive_running_promises[account] += amount }

      @register.push({
         type: :promise,
         date: date,
         from_account: self,
         to_account: account,
         amount: amount
      }.merge(register_snapshot_info([account])))
    end

  end

end

task :journal do |block|

  funds_options = self.__root__.instance_variable_get(:@options)

  current_date = nil
  task :date do |d|
    current_date = d.kind_of?(Date) ? d : Date.parse(d)
  end

  transactions_and_promises = []
  task :transaction do |payee, block|
    raise "transaction with no date" if current_date.nil?

    postings = []
    task :posting do |account, amount, block|
      raise "posting with no account" if account.nil?
      postings.push({account: account, amount: amount.nil? ? nil : ::Funds::Amount[amount]})
    end

    comments = []
    task :comment do |c|
      comments.push c
    end

    instance_exec(&block)

    if postings.empty? || postings.length == 1
      raise "transaction must have more than 1 posting"
    end

    # make sure at most one amount is nil
    nil_index = nil
    sum = ::Funds::Amount[0]
    postings.each_with_index do |posting, index|
      if posting[:amount].nil?
        raise "transaction with more than one nil amount: #{postings.inspect}" unless nil_index.nil?
        nil_index = index
      else
        sum += posting[:amount]
      end
    end
    if nil_index.nil? # no nil posting, so sum should be zero
      raise "Error, transactions postings don't sum to zero" unless sum.zero?
    else
      postings[nil_index][:amount] = sum.negate
    end
    # also, make sure we don't have the condition where there are both multiple positive postings and multiple negative postings
    num_positive_postings = 0
    num_negative_postings = 0
    postings.each do |posting|
      if posting[:amount].positive?
        num_positive_postings += 1
      elsif posting[:amount].negative?
        num_negative_postings += 1
      else
        # ignore postings with zero amount
      end
    end
    raise "Ambiguous postings (multiple positive and multiple negative):\n#{postings.to_yaml}" if num_positive_postings > 1 && num_negative_postings > 1

    transactions_and_promises.push({type: :transaction, date: current_date, postings: postings, payee: payee, comments: comments})
  end

  task :promise do |opts|
    raise "promise with no date" if current_date.nil?
    raise "promise syntax: 'promise from: <account>, to: <account>, amount: <amount>'" unless opts.kind_of?(Hash)

    raise "promise with no 'from' field"   unless opts[:from]
    raise "promise with no 'to' field"     unless opts[:to]
    raise "promise with no 'amount' field" unless opts[:amount]

    transactions_and_promises.push({type: :promise, date: current_date, from: opts[:from], to: opts[:to], amount: ::Funds::Amount[opts[:amount]]})
  end

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

    promise_block = nil
    task :promise_info do |block|
      promise_block = block
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
    raise "Amount field undefined" if (fields[:amount].nil? && (fields[:credit_amount].nil? && fields[:debit_amount].nil?))
    raise "Payee field undefined" if fields[:payee].nil?
  
    entries = nil
    begin
      entries = CSV.read(fname)
    rescue => e
      puts "Error reading file: #{fname}"
      raise e
    end
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
      elsif vars[:credit_amount] || vars[:debit_amount]
        debit  = ::Funds::Amount.new(vars[:debit_amount] || 0).negate
        credit = ::Funds::Amount.new(vars[:credit_amount] || 0)
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

      promise_info = nil
      unless promise_block.nil?
        promise_info = promise_block.call(vars)
      end
      unless skip
        date vars[:date]
        transaction vars[:payee] do
          comment_fields.each do |field|
            comment "#{field.to_s}: #{vars[field.to_sym].to_s}"
          end
          posting account, vars[:amount]
          posting ext_account
        end
        unless promise_info.nil?
          promise promise_info
        end
      end
    end
    unless group_name.nil? # duplicate prevention (only screens duplicates from OTHER import files in the same group, not from same import file)
      group_seen_rows[group_name].merge(this_group_seen_rows)
    end
  
  end

  instance_exec(&block)

  # stable sort
  transactions_and_promises = (transactions_and_promises.each_with_index.to_a.sort do |a_and_index, b_and_index|
    a, a_index = a_and_index[0], a_and_index[1]
    b, b_index = b_and_index[0], b_and_index[1]
    if a[:date] == b[:date]
      a_index <=> b_index
    else
      a[:date] <=> b[:date]
    end
  end).map {|arr| arr[0]}

  #puts transactions_and_promises.to_yaml

  register = []
  root = ::Funds::AccountNode.new('root', nil, nil, register)

  transactions_and_promises.each do |tr|
    if funds_options[:end_date] && funds_options[:end_date] <= tr[:date]
      break
    end
    if funds_options[:start_date] && funds_options[:start_date] > tr[:date]
      next
    end
    case tr[:type]
    when :transaction
      root.process_transaction(tr)
      tr[:postings].each do |posting|
        account = posting[:account]
        amount  = posting[:amount]
      end
    when :promise
      root.process_promise(tr)
    else
      raise "Unknown type: #{tr[:type]}"
    end

  end

  accounts = root.dfs_nodes

  # accounts.each do |node|
  #   if !node.leaf?
  #     register.reverse_each do |entry|
  #       if entry[:inclusive_current_balances].include?(node)
  #         puts "#{node.full_name} (inclusive)\t#{entry[:inclusive_current_balances][node]}"
  #         break
  #       end
  #     end
  #   end
  #   register.reverse_each do |entry|
  #     if entry[:leaf_current_balances].include?(node)
  #       puts "#{node.full_name}\t\t#{entry[:leaf_current_balances][node]}"
  #       break
  #     end
  #   end
  #   #puts node.full_name
  # end


  balances = Hash.new
  inclusive_balances = Hash.new
  promised_balances = Hash.new
  inclusive_promised_balances = Hash.new

  accounts.each do |account|
    # inclusive amounts and promises
    if !account.leaf?
      found = false
      register.reverse_each do |entry|
        if (entry[:inclusive_current_balances].include?(account))
          inclusive_balances[account] = entry[:inclusive_current_balances][account]
          inclusive_promised_balances[account] = entry[:inclusive_current_promised_balances][account]
          found = true
          break
        end
      end
      inclusive_balances[account] = ::Funds::Amount[0] if !found
      inclusive_promised_balances[account] = ::Funds::Amount[0] if !found
    end

    # non-inclusive amounts
    found = false
    register.reverse_each do |entry|
      if (entry[:leaf_current_balances].include?(account))
        balances[account] = entry[:leaf_current_balances][account]
        promised_balances[account] = entry[:leaf_current_promised_balances][account]
        found = true
        break
      end
    end
    balances[account] = ::Funds::Amount[0] if !found
    promised_balances[account] = ::Funds::Amount[0] if !found
         
  end


  {
   register: register,
   accounts: accounts,
   balances: balances,
   inclusive_balances: inclusive_balances,
   promised_balances: promised_balances,
   inclusive_promised_balances: inclusive_promised_balances
  }

end



