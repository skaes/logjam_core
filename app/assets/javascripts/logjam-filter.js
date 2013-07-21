/**
 * Created with JetBrains RubyMine.
 * User: peter.seliger
 * Date: 24.04.13
 * Time: 11:30
 * To change this template use File | Settings | File Templates.
 */


function install_logjam_lines_filter() {

  var
    global = this,

    $ = global.jQuery,

    DATA_NAME_SORTABLE_LOGJAM_TAGS = "logjam-tags",
    CLASSNAME_LOGJAM_TAGS_FILTER_ROOT = "logjam-tags-filter-root"
  ;

  // GUARD
  if ((typeof $ != "function") || (typeof $.attr != "function")) {
    return;
  }

  var
    ALIAS_DATA_LOGJAM_TAGS = ["data-", DATA_NAME_SORTABLE_LOGJAM_TAGS].join(""),

    ATTRIBUTE_SELECTOR_LOGJAM_TAGS = ["[", ALIAS_DATA_LOGJAM_TAGS, "]"].join(""),
    CLASSNAME_SELECTOR_LOGJAM_TAGS_FILTER_ROOT = [".", CLASSNAME_LOGJAM_TAGS_FILTER_ROOT].join(""),

    regXWhiteSpaceSequence = (/\s+/),

    getSortableItemsRoot = function () {
      return $("#single-request").find("#request-lines")[0];
    },
    getSortableItemListFromRoot = function ($itemsRoot) {
      return $itemsRoot.find(ATTRIBUTE_SELECTOR_LOGJAM_TAGS).toArray();
    },

    createTagNameListFromItems = function (itemList) {
      var tagNameTable = {};
      return itemList.reduce(function (collector, listItem) {

        return collector.concat(
          $(listItem)
          .attr(ALIAS_DATA_LOGJAM_TAGS)
          .split(regXWhiteSpaceSequence)
        );

      }, []).reduce(function (collector, tagName) {

          if (tagNameTable[tagName] !== tagName) {
            collector.push(tagNameTable[tagName] = tagName);
          }
          return collector;

      }, []);
    },

/*
    setFilterValues = function (filter, tagName) {
      filter.value = tagName;
      filter.text = tagName;
    },
*/

    createTagNameFilterFragment = function () {
      return $([

        '<div class="' + CLASSNAME_LOGJAM_TAGS_FILTER_ROOT + '">',
        '  <select size="1">',
      //'    <option value="all">show all</option>',
        '  </select>',
        '</div>'

      ].join(""))[0];
    },
    getTagNameFilterFragment = function ($itemsRoot) {
      return ($itemsRoot.find(CLASSNAME_SELECTOR_LOGJAM_TAGS_FILTER_ROOT)[0] || createTagNameFilterFragment());
    },
    removeAllFilterFragments = function ($itemsRoot) {
      $itemsRoot.find(CLASSNAME_SELECTOR_LOGJAM_TAGS_FILTER_ROOT).each(function () {
        $(this).remove();
      });
    },

    addTagNameToAllListItems = function (listItems, tagName) {
      listItems.forEach(function (item/*, idx, list*/) {

        var
          $item = $(item),
          tagNameList = $item.attr(ALIAS_DATA_LOGJAM_TAGS).split(regXWhiteSpaceSequence)
        ;
        if (tagNameList.indexOf(tagName) < 0) {
          tagNameList.push(tagName)
          $item.attr(ALIAS_DATA_LOGJAM_TAGS, tagNameList.join(" "));
        }
      });
    },
    applyTagNameFilter = function (evt) {
      var
        filterSelector = evt.target,

        tagName = filterSelector.options[filterSelector.options.selectedIndex].value,

        $itemsRoot = $(filterSelector).closest("#request-lines"),
      //$itemsRoot = $(filterSelector).parent().parent(),
        itemsRoot = $itemsRoot[0],

      //itemsList = $itemsRoot.children().toArray(),
        itemsList = $itemsRoot.find(".logline").toArray(),

        filteredItems = itemsList.reduce(function (collector, item) {
          if ($(item).attr(ALIAS_DATA_LOGJAM_TAGS).split(regXWhiteSpaceSequence).indexOf(tagName) >= 0) {
          //collector.matching.push(itemsRoot.removeChild(item));
            collector.matching.push(item);
          } else {
          //collector.unmatching.push(itemsRoot.removeChild(item));
            collector.unmatching.push(item);
          }
          return collector;

        }, {matching: [], unmatching: []})
      ;
      filteredItems.matching.forEach(function (item/*, idx, list*/) {
      //itemsRoot.appendChild(item);
        item.style.display = "";
      });
      filteredItems.unmatching.forEach(function (item/*, idx, list*/) {
      //itemsRoot.appendChild(item);
        item.style.display = "none";
      });
    },


    initializeTagNameFilters = function ($itemsRoot, tagNameList) {
      var
        filterFragment = getTagNameFilterFragment($itemsRoot),
        filterSelector = filterFragment && filterFragment.getElementsByTagName("select")[0]
      ;
      removeAllFilterFragments($itemsRoot);
      addTagNameToAllListItems($itemsRoot.find(".logline").toArray(), "all");


      if (filterSelector) {

        filterSelector.options.length = 0;
        filterSelector.options[0] = new Option("show all", "all");
/*
        if (tagNameList.length === 1) {
          setFilterValues(filterSelector.options[0], tagNameList[0]);
        } else {
          tagNameList.forEach(function (tagName, idx/ *, list* /) {
            filterSelector.options[idx + 1] = new Option(tagName, tagName);
          });
        }
*/
        tagNameList.forEach(function (tagName, idx/*, list*/) {
          filterSelector.options[idx + 1] = new Option(tagName, tagName);
        });
        $(filterSelector).bind("change", applyTagNameFilter);
      //$(filterSelector).on("change", applyTagNameFilter);

        $itemsRoot.children().eq(0).parent().prepend(filterFragment);
      //$itemsRoot.prepend(filterFragment);
      }
    },


    initialize = function () {
      var
        itemsRoot = getSortableItemsRoot(),
        $itemsRoot = itemsRoot && $(itemsRoot),

        sortableItemList  = ($itemsRoot && getSortableItemListFromRoot($itemsRoot)) || [],

        tagNameList = createTagNameListFromItems(sortableItemList)
      ;
      if (tagNameList.length) {

        initializeTagNameFilters($itemsRoot, tagNameList);
      }
    }
  ;

  initialize();

}
