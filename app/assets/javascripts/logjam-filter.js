function install_logjam_lines_filter() {
  var
  ALIAS_DATA_LOGJAM_TAGS = "data-logjam-tags",
  ATTRIBUTE_SELECTOR_LOGJAM_TAGS = "[data-logjam-tags]",
  CLASSNAME_LOGJAM_TAGS_FILTER_ROOT = "logjam-tags-filter-root",
  CLASSNAME_SELECTOR_LOGJAM_TAGS_FILTER_ROOT = ".logjam-tags-filter-root",

  regXWhiteSpaceSequence = (/\s+/)
  ;

  function createTagNameListFromItems(itemList) {
    var tagNameTable = {};
    return itemList.reduce(function (collector, listItem) {

      return collector.concat(
        $(listItem).attr(ALIAS_DATA_LOGJAM_TAGS).split(regXWhiteSpaceSequence)
      );

    }, []).reduce(function (collector, tagName) {

      if (tagNameTable[tagName] !== tagName && tagName != "") {
        collector.push(tagNameTable[tagName] = tagName);
      }
      return collector;

    }, []);
  };

  function createTagNameFilterFragment() {
    return $([
      '<span class="' + CLASSNAME_LOGJAM_TAGS_FILTER_ROOT + '">',
      '  <select size="1">',
      '  </select>',
      '</span>'
    ].join(""))[0];
  };

  function getTagNameFilterFragment($itemsRoot) {
    return ($itemsRoot.find(CLASSNAME_SELECTOR_LOGJAM_TAGS_FILTER_ROOT)[0] || createTagNameFilterFragment());
  };

  function removeAllFilterFragments($itemsRoot) {
    $itemsRoot.find(CLASSNAME_SELECTOR_LOGJAM_TAGS_FILTER_ROOT).remove();
  };

  function addTagNameToAllListItems(listItems, tagName) {
    listItems.forEach(function (item) {
      var
      $item = $(item),
      tagNameList = $item.attr(ALIAS_DATA_LOGJAM_TAGS).split(regXWhiteSpaceSequence)
      ;
      if (tagNameList.indexOf(tagName) < 0) {
        tagNameList.push(tagName);
        $item.attr(ALIAS_DATA_LOGJAM_TAGS, tagNameList.join(" "));
      }
    });
  };

  function applyTagNameFilter(evt) {
    var
    filterSelector = evt.target,

    tagName = filterSelector.options[filterSelector.options.selectedIndex].value,

    $itemsRoot = $(filterSelector).closest("#request-lines"),
    itemsRoot = $itemsRoot[0],

    itemsList = $itemsRoot.find(".logline").toArray(),

    filteredItems = itemsList.reduce(function (collector, item) {
      if ($(item).attr(ALIAS_DATA_LOGJAM_TAGS).split(regXWhiteSpaceSequence).indexOf(tagName) >= 0) {
        collector.matching.push(item);
      } else {
        collector.unmatching.push(item);
      }
      return collector;

    }, {matching: [], unmatching: []})
    ;

    filteredItems.matching.forEach(function (item) {
      item.style.display = "";
    });

    filteredItems.unmatching.forEach(function (item) {
      item.style.display = "none";
    });
  };

  function initializeTagNameFilters($itemsRoot, tagNameList) {
    var
    filterFragment = getTagNameFilterFragment($itemsRoot),
    filterSelector = filterFragment && filterFragment.getElementsByTagName("select")[0]
    ;
    removeAllFilterFragments($itemsRoot);
    addTagNameToAllListItems($itemsRoot.find(".logline").toArray(), "all");

    if (filterSelector) {
      filterSelector.options.length = 0;
      filterSelector.options[0] = new Option("show all", "all");

      tagNameList.forEach(function (tagName, idx) {
        filterSelector.options[idx + 1] = new Option(tagName, tagName);
      });
      $(filterSelector).bind("change", applyTagNameFilter);

      $itemsRoot.find('legend').append(filterFragment);
    }
  };

  function initialize() {
    var
    $itemsRoot = $("#single-request #request-lines"),
    itemsRoot = $itemsRoot[0],
    sortableItemList = $itemsRoot.find(ATTRIBUTE_SELECTOR_LOGJAM_TAGS).toArray() || [],
    tagNameList = createTagNameListFromItems(sortableItemList)
    ;

    if (tagNameList.length) {
      initializeTagNameFilters($itemsRoot, tagNameList);
    }
  };

  initialize();
}
