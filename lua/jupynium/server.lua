local M = {}

local options = require "jupynium.options"
local utils = require "jupynium.utils"

M.server_state = {
  is_autostarted = false,
  is_autoattached = false,
}

function M.jupynium_pid()
  local pid = vim.fn.trim(vim.fn.system(options.opts.python_host .. " -m jupynium --check_running"))
  if pid == "" then
    return nil
  else
    return tonumber(pid)
  end
end

function M.register_autostart_autocmds(augroup, opts)
  -- Weird thing to note
  -- BufNew will be called when you even close vim, even without opening any .ju.py file
  -- Maybe because it access to a recent file history?
  local all_patterns = {}
  if opts.auto_start_server.enable then
    for _, v in pairs(opts.auto_start_server.file_pattern) do
      table.insert(all_patterns, v)
    end
  end
  if opts.auto_attach_to_server.enable then
    for _, v in pairs(opts.auto_attach_to_server.file_pattern) do
      table.insert(all_patterns, v)
    end
  end
  if opts.auto_start_sync.enable then
    for _, v in pairs(opts.auto_start_sync.file_pattern) do
      table.insert(all_patterns, v)
    end
  end

  all_patterns = utils.remove_duplicates(all_patterns)

  vim.api.nvim_create_autocmd({ "BufWinEnter" }, {
    pattern = all_patterns,
    callback = function()
      local bufname = vim.api.nvim_buf_get_name(0)
      print "Aaa"
      if not M.server_state.is_autostarted then
        if
          opts.auto_start_server.enable
          and utils.list_wildcard_match(bufname, opts.auto_start_server.file_pattern) ~= nil
        then
          vim.cmd [[JupyniumStartAndAttachToServer]]
          M.server_state.is_autostarted = true
        end
      end

      if not M.server_state.is_autostarted and not M.server_state.is_autoattached then
        if
          opts.auto_attach_to_server.enable
          and utils.list_wildcard_match(bufname, opts.auto_attach_to_server.file_pattern) ~= nil
        then
          vim.cmd [[JupyniumAttachToServer]]
          M.server_state.is_autoattached = true
        end
      end

      if opts.auto_start_sync.enable then
        if utils.list_wildcard_match(bufname, opts.auto_start_sync.file_pattern) ~= nil then
          -- check if server is running
          if not M.server_state.is_autostarted then
            if M.jupynium_pid() == nil then
              return
            end
          end

          -- auto start sync
          if vim.fn.exists ":JupyniumStartSync" > 0 then
            vim.cmd [[JupyniumStartSync]]
          else
            if M.server_state.is_autostarted or M.server_state.is_autoattached then
              -- wait until command exists
              local found, _ = vim.wait(1000, function()
                return vim.fn.exists ":JupyniumStartSync" > 0
              end)

              if found then
                vim.cmd [[JupyniumStartSync]]
              end
            end
          end
        end
      end
    end,
    group = augroup,
  })
end

function M.add_commands()
  -- not all commands are added here.
  -- It only includes wrapper that calls Python Jupynium package.
  -- The rest of the commands will be added when you attach a server.
  vim.api.nvim_create_user_command("JupyniumStartAndAttachToServer", M.start_and_attach_to_server_cmd, { nargs = "?" })
  vim.api.nvim_create_user_command("JupyniumAttachToServer", M.attach_to_server_cmd, { nargs = "?" })
end

local function call_jupynium_cli_bg(args)
  local call_str
  if vim.fn.has "win32" == 1 then
    call_str = [[call system('PowerShell "Start-Process -FilePath \"]]
      .. vim.fn.expand(options.opts.python_host):gsub("\\", "\\\\")
      .. [[\" -ArgumentList \"-m jupynium --nvim_listen_addr ]]
      .. vim.v.servername

    for _, v in ipairs(args) do
      call_str = call_str .. [[ `\"]] .. v:gsub("\\", "\\\\") .. [[`\"]]
    end

    call_str = call_str .. [[\""')]]
  else
    call_str = [[call system('"]]
      .. vim.fn.expand(options.opts.python_host)
      .. [[" -m jupynium --nvim_listen_addr ]]
      .. vim.v.servername

    for _, v in ipairs(args) do
      call_str = call_str .. [[ "]] .. v:gsub("\\", "\\\\") .. [["]]
    end

    call_str = call_str .. [[ &')]]
  end
  vim.cmd(call_str)
end

function M.start_and_attach_to_server_cmd(args)
  local notebook_URL = vim.fn.trim(args.args)

  if notebook_URL == "" then
    call_jupynium_cli_bg { "--notebook_URL", options.opts.default_notebook_URL }
  else
    call_jupynium_cli_bg { "--notebook_URL", notebook_URL }
  end
end

function M.attach_to_server_cmd(args)
  local notebook_URL = vim.fn.trim(args.args)

  if notebook_URL == "" then
    call_jupynium_cli_bg { "--attach_only", "--notebook_URL", options.opts.default_notebook_URL }
  else
    call_jupynium_cli_bg { "--attach_only", "--notebook_URL", notebook_URL }
  end
end

return M
