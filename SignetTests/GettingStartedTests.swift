import Foundation
import Testing
@testable import Signet

/// Help > Getting Started: the book chapter rendered from Markua, and bundled with the app.
struct GettingStartedTests {
    @Test func rendersTheBlocksTheBookUses() {
        let source = """
        {#id: 110-starting_1_Getting}
        # Getting started

        Some **bold**, *italic*, `code` and a [site](https://signetwallet.org).
        A second line of the same paragraph.

        | Platform | Repository |
        |----------|------------|
        | [Mac](https://github.com/drchrispinnock/signet) | x |

        ```
        sudo apt install <signet>
        ```

        ![The disclaimer](110/Disclaimer.png)

        - one
        - two

        1. first
        2. second

        I> A note for the reader.
        """
        let html = Markua.html(from: source, title: "Getting Started")
        #expect(html.contains(#"<h1 id="110-starting_1_Getting">Getting started</h1>"#))
        #expect(html.contains("<p>Some <strong>bold</strong>, <em>italic</em>, <code>code</code> and a <a href=\"https://signetwallet.org\">site</a>. A second line of the same paragraph.</p>"))
        #expect(html.contains("<tr><th>Platform</th><th>Repository</th></tr><tr><td><a href=\"https://github.com/drchrispinnock/signet\">Mac</a></td><td>x</td></tr>"))
        #expect(html.contains("<pre><code>sudo apt install &lt;signet&gt;</code></pre>"))
        #expect(html.contains(#"<img src="110/Disclaimer.png" alt="The disclaimer">"#))
        #expect(html.contains("<ul><li>one</li><li>two</li></ul>") && html.contains("<ol><li>first</li><li>second</li></ol>"))
        #expect(html.contains(#"<aside class="info"><p>A note for the reader.</p></aside>"#))
    }

    @Test func readsBothAnchorFormsAndHidesAttributeLines() {
        let html = Markua.html(from: "{id: ID110-starting_1_Getting, sample: true}\n# Getting started\n\n{width: 80%}\nText", title: "t")
        #expect(html.contains(#"<h1 id="ID110-starting_1_Getting">Getting started</h1>"#))
        // The page's stylesheet has braces of its own; the attribute lines must not appear.
        #expect(!html.contains("{id:") && !html.contains("{width") && html.contains("<p>Text</p>"))
        #expect(Markua.anchor(in: "{#id: 110-starting_1_Getting}") == "110-starting_1_Getting")
    }

    @Test func linksWithinTheChapterStayAndOthersGoToTheBook() {
        let source = "{#id: here}\n## Here\n\nSee [here](#here), [dApps](#170-dapps_1_Distribute) and [bad](javascript:alert(1))."
        let html = Markua.html(from: source, title: "t")
        #expect(html.contains(##"<a href="#here">here</a>"##))
        #expect(html.contains(#"<a href="https://leanpub.com/read/tezossignet/170-dapps_1_Distribute">dApps</a>"#))
        #expect(!html.contains("javascript:"))
    }

    @Test func hidesAuthorNotesAndEscapesEverything() {
        let html = Markua.html(from: "Before <!-- XXX a note\nover two lines --> after <script>alert(1)</script> my_snake_case_name", title: "t")
        #expect(!html.contains("XXX") && !html.contains("<script>"))
        #expect(html.contains("Before  after &lt;script&gt;alert(1)&lt;/script&gt; my_snake_case_name"))
        // Only pictures beside the chapter.
        #expect(!Markua.html(from: "![](https://example.com/x.png)\n\n![](../../x.png)", title: "t").contains("<img"))
    }

    #if canImport(AppKit)
    /// The app carries the chapter and every picture it shows (the test host is Signet.app).
    @Test func theAppBundlesTheChapterAndItsPictures() throws {
        let html = try #require(GettingStartedView.chapterHTML())
        #expect(html.localizedCaseInsensitiveContains("<h1 id=\"ID110-starting_1_Getting\">Getting started</h1>"))
        let resources = try #require(Bundle.main.resourceURL)
        let pictures = html.components(separatedBy: "<img src=\"").dropFirst().compactMap { $0.components(separatedBy: "\"").first }
        #expect(pictures.count >= 10)
        for picture in pictures {
            #expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent(picture).path), "\(picture)")
        }
    }
    #endif
}
