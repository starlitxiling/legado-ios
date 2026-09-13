require 'tmpdir'
require 'fileutils'

output = File.expand_path(__dir__)
%w[nav ncx spine].each do |kind|
  Dir.mktmpdir('epub-fixture') do |dir|
    FileUtils.mkdir_p(File.join(dir, 'META-INF'))
    FileUtils.mkdir_p(File.join(dir, 'OPS'))
    files = {
      'mimetype' => 'application/epub+zip',
      'META-INF/container.xml' => '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
      'OPS/a.xhtml' => '<html><head><title>第一文件</title></head><body><h1 id="one">第一章</h1><p>第一段。</p><img src="cover.png" alt="插图"/><h1 id="two">第二章</h1><p>第二段。</p></body></html>',
      'OPS/b.xhtml' => '<html><head><title>补充</title></head><body><p>接续正文。</p></body></html>',
      'OPS/c.xhtml' => '<html><head><title>最后文件</title></head><body><h1 id="three">第三章</h1><p>最后一段。</p></body></html>',
      'OPS/cover.png' => 'synthetic-image',
      'OPS/nav.xhtml' => '<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="a.xhtml#one">一</a></li><li><a href="a.xhtml#two">二</a></li><li><a href="c.xhtml#three">三</a></li></ol></nav></body></html>',
      'OPS/toc.ncx' => '<ncx><navMap><navPoint><navLabel><text>一</text></navLabel><content src="a.xhtml#one"/><navPoint><navLabel><text>二</text></navLabel><content src="a.xhtml#two"/></navPoint></navPoint><navPoint><navLabel><text>三</text></navLabel><content src="c.xhtml#three"/></navPoint></navMap></ncx>'
    }
    nav = kind == 'nav' ? '<item id="nav" href="nav.xhtml" properties="nav" media-type="application/xhtml+xml"/>' : ''
    ncx = kind == 'ncx' ? '<item id="toc" href="toc.ncx" media-type="application/x-dtbncx+xml"/>' : ''
    files['OPS/book.opf'] = '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>合成书</dc:title><dc:creator>合成作者</dc:creator><meta name="cover" content="cover"/></metadata><manifest><item id="c" href="c.xhtml"/><item id="b" href="b.xhtml"/><item id="a" href="a.xhtml"/><item id="cover" href="cover.png"/>' + nav + ncx + '</manifest><spine toc="toc"><itemref idref="a"/><itemref idref="b"/><itemref idref="c"/></spine></package>'
    files.each { |name, data| File.binwrite(File.join(dir, name), data) }
    destination = File.join(output, "#{kind}.epub")
    FileUtils.rm_f(destination)
    Dir.chdir(dir) do
      abort 'zip failed' unless system('/usr/bin/zip', '-q', '-X', '-0', destination, 'mimetype')
      abort 'zip failed' unless system('/usr/bin/zip', '-q', '-X', '-r', destination, 'META-INF', 'OPS')
    end
  end
end
