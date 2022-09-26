unified_mode true

property :config_file, String, default: lazy { node['consul']['config']['path'] }
property :user, String, default: lazy { node['consul']['service_user'] }
property :group, String, default: lazy { node['consul']['service_group'] }
property :environment, Hash, default: lazy { default_environment }
property :data_dir, String, default: lazy { node['consul']['config']['data_dir'] }
property :config_dir, String, default: lazy { node['consul']['config_dir'] }
property :nssm_params, Hash, default: lazy { node['consul']['service']['nssm_params'] }
property :systemd_params, Hash, default: lazy { node['consul']['service']['systemd_params'] }
property :program, String, default: '/usr/local/bin/consul'
property :acl_token, String, default: lazy { node['consul']['config']['acl_master_token'] }
property :restart_on_update, [true, false], default: true
property :version, String, default: lazy { node['consul']['version'] }

def shell_environment
  shell = node['consul']['service_shell']
  shell.nil? ? {} : { 'SHELL' => shell }
end

def default_environment
  {
    'GOMAXPROCS' => [node['cpu']['total'], 2].max.to_s,
    'PATH' => '/usr/local/bin:/usr/bin:/bin',
  }.merge(shell_environment)
end

action_class do
  include ConsulCookbook::Helpers
end

action :enable do
  directory new_resource.data_dir do
    recursive true
    owner new_resource.user
    group new_resource.group
    mode '0750'
  end

  if platform_family?('rhel') && node['platform_version'].to_i == 6
    template('/etc/init.d/consul') do
      source 'sysvinit.service.erb'
      owner new_resource.user
      group new_resource.group
      variables(
        daemon: "/opt/consul/#{new_resource.version}/consul",
        daemon_options: "agent -config-file=#{new_resource.config_file} -config-dir=#{new_resource.config_dir}",
        environment: new_resource.environment.map,
        name: 'consul',
        pid_file: '/var/run/consul.pid',
        reload_signal: 'HUP',
        stop_signal: 'TERM',
        user: new_resource.user
      )
      mode '744'
      action :create
      notifies :restart, 'service[consul]' if new_resource.restart_on_update
    end

    service 'consul' do
      action :enable
    end
  else
    systemd_unit 'consul.service' do
      content(
        Unit: {
          Description: 'consul',
          Wants: 'network-online.target',
          After: 'network-online.target',
          ConditionFileNotEmpty: new_resource.config_file,
        },
        Service: {
          Environment: new_resource.environment.map { |key, val| %("#{key}=#{val}") }.join(' '),
          ExecStart: command(new_resource.config_file, new_resource.config_dir, new_resource.program),
          ExecReload: '/bin/kill --signal HUP $MAINPID',
          KillMode: 'process',
          KillSignal: 'SIGTERM',
          User: new_resource.user,
          Group: new_resource.group,
          WorkingDirectory: new_resource.data_dir,
          Restart: 'on-failure',
          LimitNOFILE: 65536,
        }.merge(new_resource.systemd_params),
        Install: {
          WantedBy: 'multi-user.target',
        }
      )
      notifies :restart, 'service[consul]' if new_resource.restart_on_update
      action %i(create enable)
    end
  end

  service 'consul' do
    action :nothing
  end
end

action :start do
  service 'consul' do
    action :start
  end
end

action :reload do
  service 'consul' do
    action :reload
  end
end

action :restart do
  service 'consul' do
    action :restart
  end
end

action :disable do
  service 'consul' do
    action :stop
  end

  if platform_family?('rhel') && node['platform_version'].to_i == 6
    service 'consul.service' do
      action :disable
    end
  else
    systemd_unit 'consul.service' do
      action %i(disable delete)
    end
  end
end

action :stop do
  service 'consul' do
    action :stop
  end
end
