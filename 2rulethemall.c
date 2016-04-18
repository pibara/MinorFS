//MinorFs POLP/POLA proof of concept filesystem kit
//Copyright (C) Rob J Meijer 2008  <minorfs@polacanthus.net>
//
//This library is free software; you can redistribute it and/or
//modify it under the terms of the GNU Lesser General Public
//License as published by the Free Software Foundation; either
//version 2.1 of the License, or (at your option) any later version.
//
//This library is distributed in the hope that it will be useful,
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
//Lesser General Public License for more details.
//
//You should have received a copy of the GNU Lesser General Public
//License along with this library; if not, write to the Free Software
//Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA
#define _GNU_SOURCE
#include <sys/types.h>
#include <pwd.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <grp.h>
#include <string.h>

int main(int argc, char **argv) {
  char link[101];
  char passwordfile[201];
  FILE *passfil;
  memset((void *)link,0, 101);
  memset((void *)passwordfile,0, 201); 
  readlink("/mnt/minorfs/priv/home", link, 100);
  snprintf(passwordfile, 200,"%s/onetorulethemall", link);
  passfil=fopen(passwordfile, "r"); 
  if (passfil) {
    char *line=0;
    char *line2=0;
    size_t len;
    size_t len2;
    getline(&line, &len, passfil);
    fclose(passfil);
    printf("2rulethemall password:");
    getline(&line2, &len2, stdin);
    if (len && len2 && (len == len2)) {
      if (strncmp(line,line2,len) == 0) {
         printf("2rulethemall path=%s\n",link);
         return 0;
      } else {
        printf("2rulethemall invalid\n");
      }
    }
  } else {
     printf("2rulethemall NO PASSWORD SET !!!\n\nNew password:");
     char *line=0;
     size_t len;
     getline(&line, &len, stdin);
     if (len > 10) {
       passfil=fopen(passwordfile, "w");
       if (passfil) {
          fprintf(passfil,"%s\n",line);
          fclose(passfil);
       }
       else {
           printf("2rulethemall ERROR: unable to create password file\n");
           return 1;
       }
     } else {
       printf("2rulethemall PASSWORD TO SHORT !!\n");
       return 1;
     }
   
  } 
  return 0;
}
