class nagios::check::fluentbit (
  Enum['present','absent']           $ensure                   = 'present',
  Array[String]                      $modes_enabled            = [],
  Array[String]                      $modes_disabled           = [],
  Optional[Hash[String, String]]     $mode_args                = {},
  Optional[String]                   $check_title              = $::nagios::client::host_name,
  Optional[String]                   $check_period             = $::nagios::client::service_check_period,
  Optional[String]                   $contact_groups           = $::nagios::client::service_contact_groups,
  Optional[String]                   $first_notification_delay = $::nagios::client::service_first_notification_delay,
  Optional[String]                   $max_check_attempts       = $::nagios::client::service_max_check_attempts,
  Optional[String]                   $notification_period      = $::nagios::client::service_notification_period,
  Optional[String]                   $use                      = $::nagios::client::service_use,
  Optional[String]                   $servicegroups            = $::nagios::client::service_servicegroups,
  Optional[String]                   $check_script_path        = '/usr/lib64/nagios/plugins/check_systemd_service.sh',
) {

  # Let's check if the systemd check script is present and if not copy it
  file { $check_script_path:
    ensure => $ensure,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => "puppet:///modules/${module_name}/scripts/check_systemd_service.sh",
  }

  # Define all supported modes
  $all_modes = ['status', 'memory_usage', 'uptime']

  # Determine effective modes based on provided parameters
  if !$modes_enabled.empty() {
    $effective_modes = $modes_enabled
  } elsif !$modes_disabled.empty() {
    # Subtract disabled modes from all modes
    $effective_modes = $all_modes.filter |$mode| { !$modes_disabled.include($mode) }
    # Fail if no enabled modes are left
    if $effective_modes.empty() {
      fail("All modes have been disabled, leaving no enabled modes.")
    }
  } else {
    # If neither modes_enabled nor modes_disabled is provided, enable all modes
    $effective_modes = $all_modes
  } 

  # Define NRPE checks for enabled modes
  $effective_modes.each |$mode| {
    if !($mode in $modes_disabled) {
      $mode_specific_args = $mode_args[$mode] ? {
        undef   => '',
        default => $mode_args[$mode],
      }

      $args = "-m ${mode} ${mode_specific_args} -s fluent-bit"

      nagios::client::nrpe_file { "check_fluentbit_${mode}":
        ensure  => $ensure,
        plugin  => 'check_systemd_service.sh',
        args    => $args,
        require => File[$check_script_path],
      }

      nagios::service { "check_fluentbit_${mode}_${check_title}":
        ensure                   => $ensure,
        check_command            => "check_nrpe_fluentbit_${mode}",
        service_description      => "fluentbit_${mode}",
        check_period             => $check_period,
        notification_period      => $notification_period,
        contact_groups           => $contact_groups,
        first_notification_delay => $first_notification_delay,
        max_check_attempts       => $max_check_attempts,
        use                      => $use,
        servicegroups            => $servicegroups,
      }
    }
  }
}
