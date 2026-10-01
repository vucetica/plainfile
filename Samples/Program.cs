using System;
using System.Collections.Generic;
using System.Linq;

namespace Sample
{
    /// <summary>Entry point.</summary>
    public static class Program
    {
        private const int MaxItems = 10;

        public static async Task<int> Main(string[] args)
        {
            var items = Enumerable.Range(1, MaxItems).Select(i => $"Item {i}").ToList();
            string path = @"C:\temp\file.txt";
            foreach (var item in items)
            {
                Console.WriteLine(item); // print each
            }
            /* multi-line
               comment */
            return items.Count > 0 ? 0 : 1;
        }
    }
}
