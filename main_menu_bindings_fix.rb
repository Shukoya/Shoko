# frozen_string_literal: true

# Fixed menu bindings using proper Input::CommandFactory patterns

def register_menu_bindings
  bindings = Input::CommandFactory.navigation_commands(nil, :selected, lambda { |_ctx|
    5 # 6 menu items (0-5)
  })
  bindings.merge!(Input::CommandFactory.menu_selection_commands)

  # Main menu quit (quit entire application)
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.cleanup_and_exit(0, '')
      :handled
    }
  end

  @dispatcher.register_mode(:menu, bindings)
end

def register_browse_bindings
  bindings = Input::CommandFactory.navigation_commands(nil, :browse_selected, lambda { |ctx|
    (ctx.instance_variable_get(:@filtered_epubs)&.length || 1) - 1
  })

  # Browse-specific selection: open selected book
  Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.open_selected_book
      :handled
    }
  end

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:browse, bindings)
end

def register_recent_bindings
  # CRITICAL: Use :selected for recent mode since there's no recent_selected in GlobalState
  bindings = Input::CommandFactory.navigation_commands(nil, :selected, lambda { |ctx|
    (ctx.instance_variable_get(:@filtered_epubs)&.length || 1) - 1
  })

  # Recent-specific selection: open selected recent book
  Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.open_selected_book
      :handled
    }
  end

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:recent, bindings)
end

def register_settings_bindings
  # Use :selected for settings since there's no settings_selected in GlobalState
  bindings = Input::CommandFactory.navigation_commands(nil, :selected, lambda { |_ctx|
    10 # Estimated settings options
  })

  # Settings-specific selection: handle setting change
  Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.handle_settings_input(key)
      :handled
    }
  end

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:settings, bindings)
end

def register_annotations_bindings
  # Use :selected for annotations since there's no annotations_selected in GlobalState
  bindings = Input::CommandFactory.navigation_commands(nil, :selected, lambda { |ctx|
    (ctx.state.annotations&.length || 1) - 1
  })

  # Annotations-specific selection: open/edit annotation
  Input::KeyDefinitions::ACTIONS[:confirm].each do |key|
    bindings[key] = ->(_ctx, _) { :handled } # Placeholder for now
  end

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:annotations, bindings)
end

def register_search_bindings
  bindings = Input::CommandFactory.text_input_commands(:search_query)

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:search, bindings)
end

def register_open_file_bindings
  bindings = Input::CommandFactory.text_input_commands(:file_input)

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:open_file, bindings)
end

def register_annotation_editor_bindings
  bindings = Input::CommandFactory.text_input_commands(:search_query)

  # Go back to main menu
  Input::KeyDefinitions::ACTIONS[:quit].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end
  Input::KeyDefinitions::ACTIONS[:cancel].each do |key|
    bindings[key] = lambda { |ctx, _|
      ctx.state.menu_mode = :menu
      :handled
    }
  end

  @dispatcher.register_mode(:annotation_editor, bindings)
end
