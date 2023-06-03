# This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
import os
import platform
import shlex
import socket
import sys
import requests

_hostname = socket.gethostname()

def tag_value(value):
    value = str(value)
    for escape in [',', '=', ' ']:
        value = value.replace(escape, '\\' + escape)
    return value

def field_value(value):
    # Line protocol requires all strings to be quoted
    if not isinstance(value, str):
        return str(value).lower()

    # String values must always be surrounded in unescaped double quotes, while escaping inner quotes with a
    # backslash.
    return '"' + value.replace('"', '\\"') + '"'

class InfluxReporter:
    def __init__(self, args):
        self.args = args
        self.lines = []

    def _send_line_message(self, tags, fields):
        tags_str = ','.join(sorted(tags))
        fields_str = ','.join(fields)
        line_message = f'robench,{tags_str} {fields_str}'

        self.lines.append(line_message)
        if self.args.print_influx_debugging:
            print(f'[influx] {line_message}')

    def flush(self, process_exit_code):
        if self.args.report_metrics:
            print('Reporting results to Influx.')
            request = '\n'.join(self.lines)
            try:
                # We don't want a failure to report metrics to influx to result in a failed test suite.
                # Just log a warning instead.
                response = requests.post(url=self.args.report_metrics, data=request)
            except Exception as e:
                print(f"Unable to report metrics to influx.  Reason: {str(e)}")
                print('Request content (for debugging): ')
                print(request)

    def report_result(self, testFolder, testName, testPath, status, timeMin, timeAvg, timeMax, confInt, vmName, vmPath):
        is_teamcity = 'TEAMCITY_PROJECT_NAME' in os.environ
        tags = [
            f'hostname={tag_value(_hostname)}',
            f'is_teamcity={tag_value(is_teamcity)}',
            f'platform={tag_value(sys.platform)}',
            'type=event',
            'priority=high',
            f'test_folder={tag_value(testFolder)}',
            f'test_name={tag_value(testName)}',
            f'test_path={tag_value(testPath)}',
            f'vm_name={tag_value(vmName)}',
            f'vm_path={tag_value(vmPath)}',
        ]
        fields = [
            f'status={field_value(status)}',
            f'time_min={timeMin}',
            f'time_avg={timeAvg}',
            f'time_max={timeMax}',
            f'time_conf_int={confInt}',
        ]

        self._send_line_message(tags, fields)
