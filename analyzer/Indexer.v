// MIT License
//
// Copyright (c) 2023-2024 V Open Source Community Association (VOSCA) vosca.dev
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
module analyzer

import os
import time
import loglib
import analyzer.index

// IndexingRootsStatus describes the indexing status of all roots.
pub enum IndexingRootsStatus {
	all_indexed
	needs_ensure_indexed // when at least one of the indexes was taken from the cache
}

// Indexer encapsulates the indexing logic and provides an interface for working with the index.
pub struct Indexer {
pub mut:
	roots   []&index.IndexingRoot
	no_save bool
}

pub fn new_indexer() &Indexer {
	return &Indexer{}
}

pub fn (mut i Indexer) set_no_save(value bool) {
	i.no_save = value
	for mut root in i.roots {
		root.no_save = value
	}
}

pub fn (i Indexer) count_roots() int {
	return i.roots.len
}

pub fn (mut i Indexer) add_indexing_root(root string, kind index.IndexingRootKind, cache_dir string) {
	loglib.with_fields({
		'root': root
	}).info('Adding indexing root')
	i.roots << index.new_indexing_root(root, kind, cache_dir)
}

pub fn (mut i Indexer) index(on_start fn (root index.IndexingRoot, index int)) IndexingRootsStatus {
	now := time.now()
	loglib.info('Indexing ${i.roots.len} roots')

	mut need_ensure_indexed := false

	for index, mut indexing_root in i.roots {
		on_start(*indexing_root, index + 1)
		status := indexing_root.index()
		if status == .from_cache {
			// If at least one of the indexes was taken from the cache,
			// then we need to make sure that all indexes are up to date.
			need_ensure_indexed = true
		}
	}

	loglib.with_duration(time.since(now)).info('Indexing all roots')

	return if need_ensure_indexed {
		.needs_ensure_indexed
	} else {
		.all_indexed
	}
}

pub fn (mut i Indexer) ensure_indexed() {
	now := time.now()
	loglib.info('Ensure indexed of ${i.roots.len} roots')

	for mut indexing_root in i.roots {
		indexing_root.ensure_indexed()
	}

	loglib.with_duration(time.since(now)).info('Ensure indexed of all roots')
}

pub fn (mut i Indexer) save_indexes() ! {
	if i.no_save {
		return
	}

	for mut indexing_root in i.roots {
		indexing_root.save_index() or {
			loglib.with_fields({
				'root': indexing_root.root
				'err':  err.str()
			}).error('Failed to save index')
			return err
		}
	}
}

pub fn (mut i Indexer) mark_as_dirty(filepath string, new_content string) ! {
	for mut indexing_root in i.roots {
		indexing_root.mark_as_dirty(filepath, new_content)!
	}
}

pub fn (mut i Indexer) add_file(path string) ?index.FileIndex {
	content := os.read_file(path) or {
		loglib.with_fields({
			'path': path
			'err':  err.str()
		}).error('Failed to read new file')
		return none
	}

	for mut root in i.roots {
		if root.contains(path) {
			return root.add_file(path, content) or {
				loglib.with_fields({
					'root': root.root
					'path': path
					'err':  err.str()
				}).error('Failed to add new file')
				return none
			}
		}
	}

	return none
}

pub fn (mut i Indexer) rename_file(old_path string, new_path string) ?index.FileIndex {
	for mut root in i.roots {
		if root.contains(old_path) {
			return root.rename_file(old_path, new_path) or {
				loglib.with_fields({
					'root':     root.root
					'old_path': old_path
					'new_path': new_path
					'err':      err.str()
				}).error('Failed to rename file')
				continue
			}
		}
	}

	return none
}

pub fn (mut i Indexer) remove_file(path string) ?index.FileIndex {
	for mut root in i.roots {
		if root.contains(path) {
			return root.remove_file(path) or {
				loglib.with_fields({
					'root': root.root
					'path': path
					'err':  err.str()
				}).error('Failed to remove file')
				continue
			}
		}
	}

	return none
}
