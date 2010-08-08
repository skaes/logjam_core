Yesterday = ControllerAction.class_for_date(Date.yesterday.to_s) unless defined? Yesterday
Yesterday.ensure_table_exists
