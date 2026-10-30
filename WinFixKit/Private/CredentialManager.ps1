# Thin wrapper over the Windows Credential Manager API (advapi32). It lists targets and deletes
# entries only. It never reads the stored secret. Using the API instead of parsing "cmdkey /list"
# keeps it working on non-English Windows.

$script:CredManSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WinFixKit
{
    public class StoredCredentialInfo
    {
        public string Target;
        public int Type;
        public string UserName;
        public int Persist;
        public DateTime LastWritten;
    }

    public static class CredMan
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL
        {
            public int Flags;
            public int Type;
            public IntPtr TargetName;
            public IntPtr Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public IntPtr TargetAlias;
            public IntPtr UserName;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredEnumerateW(string filter, int flags, out int count, out IntPtr credentials);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDeleteW(string target, int type, int flags);

        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);

        public static List<StoredCredentialInfo> Enumerate()
        {
            var list = new List<StoredCredentialInfo>();
            int count;
            IntPtr items;
            if (!CredEnumerateW(null, 0, out count, out items))
            {
                int error = Marshal.GetLastWin32Error();
                if (error == 1168) { return list; } // ERROR_NOT_FOUND: no stored credentials
                throw new Win32Exception(error);
            }
            try
            {
                for (int i = 0; i < count; i++)
                {
                    IntPtr ptr = Marshal.ReadIntPtr(items, i * IntPtr.Size);
                    var c = (CREDENTIAL)Marshal.PtrToStructure(ptr, typeof(CREDENTIAL));
                    long fileTime = ((long)c.LastWritten.dwHighDateTime << 32) | (uint)c.LastWritten.dwLowDateTime;
                    list.Add(new StoredCredentialInfo
                    {
                        Target = Marshal.PtrToStringUni(c.TargetName),
                        Type = c.Type,
                        UserName = c.UserName == IntPtr.Zero ? null : Marshal.PtrToStringUni(c.UserName),
                        Persist = c.Persist,
                        LastWritten = DateTime.FromFileTime(fileTime)
                    });
                }
            }
            finally
            {
                CredFree(items);
            }
            return list;
        }

        public static void Delete(string target, int type)
        {
            if (!CredDeleteW(target, type, 0)) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
        }
    }
}
'@

function Initialize-FixKitCredMan {
    if (-not ('WinFixKit.CredMan' -as [type])) {
        Add-Type -TypeDefinition $script:CredManSource -Language CSharp -ErrorAction Stop
    }
}

function ConvertTo-CredentialTypeName {
    param([int]$Type)
    switch ($Type) {
        1 { 'Generic' }
        2 { 'Windows' }
        3 { 'Certificate' }
        4 { 'Windows (visible)' }
        default { "Type $Type" }
    }
}
