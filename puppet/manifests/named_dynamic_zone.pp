# == Class: named:dynamic_zone
#
# Create a named zone which allows dynamic updates
#
# === Parameters
#
# String: zone
#
# === Examples
#
# puppet apply named_dynamic_zone.pp --zone = app.example.com
#
# === Copyright
#
# Copyright 2013 Mojo Lingo LLC.
# Copyright 2013 Red Hat, Inc.
#
# === License
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
class named::dynamic_zone($zone) {

  notify {"dynamic zone: ${zone}":}
  # require packages 
}

class {'named::dynamic_zone':
  zone => 'example.com',
}
