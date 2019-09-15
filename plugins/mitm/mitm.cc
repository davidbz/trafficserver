/** @file

  tcpinfo: A plugin to log TCP session information.

  @section license License

  Licensed to the Apache Software Foundation (ASF) under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ASF licenses this file
  to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
 */

#include <cstdio>
#include <cstdlib>
#include <memory>
#include <ts/ts.h>
#include <unistd.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <climits>
#include <cstring>
#include <cerrno>
#include <sys/time.h>
#include <arpa/inet.h>

#include "tscore/ink_defs.h"

#define PLUGIN_NAME "mitm"

static int
read_request_cb(TSCont contp ATS_UNUSED, TSEvent event, void *edata)
{
  TSReleaseAssert(event == TS_EVENT_HTTP_READ_REQUEST_HDR);

  TSHttpTxn txn = (TSHttpTxn)edata;

  TSMBuffer buffer;
  TSMLoc location;
  TSHttpTxnClientReqGet(txn, &buffer, &location);

  // Lets skip remap
  TSSkipRemappingSet(txn, 1);

  int method_str_length;
  const char *const method = TSHttpHdrMethodGet(buffer, location, &method_str_length);
  int host_str_length;
  const char* const hostname = TSHttpHdrHostGet(buffer, location, &host_str_length);

  struct sockaddr const *addr = TSHttpTxnClientAddrGet(txn);

  // IPv4 only
  char source_ip[24];
  inet_ntop(AF_INET, &(((struct sockaddr_in *)addr)->sin_addr), source_ip, 24);
  

  TSDebug(PLUGIN_NAME, "Reading request from source IP: %s. Method: %.*s to %.*s", source_ip, method_str_length, method, host_str_length, hostname);

  if (method_str_length == TS_HTTP_LEN_CONNECT && memcmp(TS_HTTP_METHOD_CONNECT, method, TS_HTTP_LEN_CONNECT) == 0) {
    union {
      struct sockaddr_in sin4;
      struct sockaddr_in6 sin6;
      struct sockaddr sa;
    } addr;

    addr.sin4.sin_family = AF_INET;
    addr.sin4.sin_port   = htons(1337);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin4.sin_addr);

    TSHttpTxnServerAddrSet(txn, &addr.sa);
  }

  TSHandleMLocRelease(buffer, TS_NULL_MLOC, location);

  // Reenable HTTP state
  TSHttpTxnReenable(txn, TS_EVENT_HTTP_CONTINUE);
  return TS_EVENT_NONE;
}

void
TSPluginInit(int argc, const char *argv[])
{
  TSPluginRegistrationInfo info;
  info.plugin_name   = (char *)"mitm";
  info.vendor_name   = (char *)"Symantec";
  info.support_email = (char *)"david@fire.glass";

  if (TSPluginRegister(&info) != TS_SUCCESS) {
    TSError("plugin registration failed");
  }

  TSCont cont_read_request_cb = TSContCreate(read_request_cb, NULL);
  TSHttpHookAdd(TS_HTTP_READ_REQUEST_HDR_HOOK, cont_read_request_cb);
}
